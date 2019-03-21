#!/bin/bash

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

export AWS_DEFAULT_REGION=${aws_region}
SELF_PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"

# aws ssm get-parameter \
#   --name "/vault/${vault_cluster_name}/vault.pem" \
# | jq -r '.Parameter.Value' \
# > /etc/vault.d/vault.pem

# aws ssm get-parameter \
#   --name "/vault/${vault_cluster_name}/vault-key.pem" \
#   --with-decryption \
# | jq -r '.Parameter.Value' \
# > /etc/vault.d/vault-key.pem

export DD_API_KEY="$(aws ssm get-parameter --name "/vault/${vault_cluster_name}/dd_api_key" --with-decryption | jq -r '.Parameter.Value')"
bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"

cat <<EOF > /etc/vault.d/vault.hcl
ui = true

storage "s3" {
  region     = "${aws_region}"
  bucket     = "${s3_bucket}"
  kms_key_id = "${kms_key_id}"
}

ha_storage "dynamodb" {
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
#  tls_cert_file   = "/etc/vault.d/vault.pem"
#  tls_key_file    = "/etc/vault.d/vault-key.pem"
  tls_disable     = "true"
}

telemetry {
  dogstatsd_addr = "127.0.0.1:8125"
  dogstatsd_tags = []
}

cluster_addr  = "https://$SELF_PRIVATE_IP:8201"
api_addr      = "https://$SELF_PRIVATE_IP:8200"
EOF

# Enable and start the Vault server agent
systemctl enable vault
systemctl start vault
