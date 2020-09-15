#!/bin/bash

set -e

#--------------------------------------------------------------------
# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
#--------------------------------------------------------------------
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

#--------------------------------------------------------------------
# Set useful variables
#--------------------------------------------------------------------
export AWS_DEFAULT_REGION=${aws_region}
SELF_PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"

#--------------------------------------------------------------------
# Install Datadog Agent
#--------------------------------------------------------------------
export DD_API_KEY="$(aws ssm get-parameter --name "${ssm_path_datadog_api_key}" --with-decryption | jq -r '.Parameter.Value')"
bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"

mkdir -p /etc/datadog-agent/conf.d/http_check.d
cat > /etc/datadog-agent/conf.d/http_check.d/conf.yaml <<EOF
init_config:

instances:
  - name: vault_http_check
    url: https://${cluster_fqdn}
EOF
systemctl restart datadog-agent

#--------------------------------------------------------------------
# Install Sumo Logic Collector
#--------------------------------------------------------------------
mkdir -p /opt/SumoCollector

cat > /opt/SumoCollector/sources.json <<EOF
{
  "api.version": "v1",
  "sources": [
    {
      "name": "SyslogMessages",
      "sourceType": "LocalFile",
      "automaticDateParsing": true,
      "multilineProcessingEnabled": false,
      "useAutolineMatching": true,
      "forceTimeZone": false,
      "timeZone": "UTC",
      "category": "Vault/${cluster_name}",
      "pathExpression": "/var/log/messages"
    },
    {
      "name": "SyslogSecure",
      "sourceType": "LocalFile",
      "automaticDateParsing": true,
      "multilineProcessingEnabled": false,
      "useAutolineMatching": true,
      "forceTimeZone": false,
      "timeZone": "UTC",
      "category": "Vault/${cluster_name}",
      "pathExpression": "/var/log/secure"
    },
    {
      "name": "VaultAudit",
      "sourceType": "LocalFile",
      "automaticDateParsing": true,
      "multilineProcessingEnabled": false,
      "useAutolineMatching": true,
      "forceTimeZone": false,
      "timeZone": "UTC",
      "category": "Vault/${cluster_name}",
      "pathExpression": "/var/log/vault/audit.log"
    }
  ]
}
EOF

SUMO_ACCESS_ID="$(aws ssm get-parameter --name "${ssm_path_sumo_access_id}" | jq -r '.Parameter.Value')"
SUMO_ACCESS_KEY="$(aws ssm get-parameter --name "${ssm_path_sumo_access_key}" --with-decryption | jq -r '.Parameter.Value')"
wget "https://collectors.sumologic.com/rest/download/linux/64" -O SumoCollector.sh
chmod +x SumoCollector.sh
./SumoCollector.sh -q \
  -dir="/opt/SumoCollector" \
  -Vsumo.accessid="$SUMO_ACCESS_ID" \
  -Vsumo.accesskey="$SUMO_ACCESS_KEY" \
  -Vdescription="Vault cluster ${cluster_name}" \
  -VsyncSources="/opt/SumoCollector/sources.json" \
  -Vephemeral=true

#--------------------------------------------------------------------
# Configure Logrotate ('EOF' so the subshell doesn't execute)
#--------------------------------------------------------------------
cat > /etc/logrotate.d/vault-audit <<'EOF'
"/var/log/vault/audit.log" {
  hourly
  rotate 2
  size 200M
  nodateext
  nocreate
  nocopy
  missingok
  notifempty
  compress
  postrotate
    kill -HUP $(cat /var/run/vault/vault.pid)
  endscript
}
EOF

# setting hourly has no effect unless logrotate actually runs hourly using cron
mv /etc/cron.daily/logrotate /etc/cron.hourly/

#--------------------------------------------------------------------
# Generate Vault's TLS certificate and key
#--------------------------------------------------------------------
openssl req \
  -x509 \
  -newkey rsa:2048 \
  -days 730 \
  -sha256 \
  -nodes \
  -subj "/CN=vault" \
  -keyout /etc/vault.d/vault-key.pem \
  -out /etc/vault.d/vault.pem

chown vault:vault /etc/vault.d/vault.pem /etc/vault.d/vault-key.pem
chmod 600 /etc/vault.d/vault.pem /etc/vault.d/vault-key.pem

#--------------------------------------------------------------------
# Configure and start Vault
#--------------------------------------------------------------------
mkdir -p /var/run/vault
chown vault:vault /var/run/vault

mkdir -p /var/log/vault
chown vault:vault /var/log/vault

cat <<EOF > /etc/vault.d/vault.hcl
ui = true
pid_file = "/var/run/vault/vault.pid"
cluster_name = "${cluster_name}"
log_format = "json"

storage "dynamodb" {
  ha_enabled = "true"
  region     = "${aws_region}"
  table      = "${dynamodb_table}"
}

seal "awskms" {
  region     = "${aws_region}"
  kms_key_id = "${kms_key_id}"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file   = "/etc/vault.d/vault.pem"
  tls_key_file    = "/etc/vault.d/vault-key.pem"
}

telemetry {
  dogstatsd_addr = "127.0.0.1:8125"
  dogstatsd_tags = ${dogstatsd_tags}
}

cluster_addr  = "https://$SELF_PRIVATE_IP:8201"
api_addr      = "https://$SELF_PRIVATE_IP:8200"
EOF

systemctl enable vault
systemctl start vault
