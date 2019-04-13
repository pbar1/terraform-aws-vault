#!/bin/bash

set -e

#--------------------------------------------------------------------
# Send the log output from this script to user-data.log, syslog, and
# the console
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

#--------------------------------------------------------------------
# Pull Vault's TLS certificates from SSM Parameter Store
#--------------------------------------------------------------------

aws ssm get-parameter --name "${ssm_path_vault_cert}" | jq -r '.Parameter.Value' > /etc/vault.d/vault.pem
aws ssm get-parameter --name "${ssm_path_vault_key}" --with-decryption | jq -r '.Parameter.Value' > /etc/vault.d/vault-key.pem

# Assume errors from pulling intermediate mean it doesn't exist and isn't needed
aws ssm get-parameter --name "${ssm_path_vault_intermediate}" | jq -r '.Parameter.Value' 2> /dev/null >> /etc/vault.d/vault.pem

chown vault:vault /etc/vault.d/vault.pem /etc/vault.d/vault-key.pem
chmod 600 /etc/vault.d/vault.pem /etc/vault.d/vault-key.pem

#--------------------------------------------------------------------
# Configure and start Vault
#--------------------------------------------------------------------

mkdir -p /var/run/vault
chown vault:vault /var/run/vault

cat <<EOF > /etc/vault.d/vault.hcl
ui       = true
pid_file = "/var/run/vault/vault.pid"

storage "s3" {
  region     = "${aws_region}"
  bucket     = "${s3_bucket}"
  kms_key_id = "${kms_key_id}"
}

ha_storage "dynamodb" {
  ha_enabled = true
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
