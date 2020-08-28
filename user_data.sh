#!/bin/bash

set -e

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

export AWS_DEFAULT_REGION=${aws_region}
SELF_PRIVATE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"

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
  tls_cert_file   = "/etc/vault.d/vault.pem"
  tls_key_file    = "/etc/vault.d/vault-key.pem"
}

telemetry {
  dogstatsd_addr = "127.0.0.1:8125"
  dogstatsd_tags = []
}

cluster_addr  = "https://$SELF_PRIVATE_IP:8201"
api_addr      = "https://$SELF_PRIVATE_IP:8200"
EOF

openssl ecparam -out /etc/vault.d/vault-key.pem -name prime256v1 -genkey
openssl req -new -key /etc/vault.d/vault-key.pem -out cert.csr -subj "/CN=$(hostname)"

cert_arn=$(aws acm-pca issue-certificate \
--certificate-authority-arn ${acm_pca_arn} \
--csr file://cert.csr \
--signing-algorithm "SHA256WITHECDSA" \
--validity Value=1,Type="YEARS" | jq -r .CertificateArn)

cert=$(aws acm-pca get-certificate \
--certificate-authority-arn ${acm_pca_arn} \
--certificate-arn $cert_arn)

echo $cert | jq -r .Certificate > /etc/vault.d/vault.pem
echo $cert | jq -r .CertificateChain >> /etc/vault.d/vault.pem

chown --recursive vault:vault /etc/vault.d
chmod 640 /etc/vault.d/*.pem

# Enable and start the Vault server agent
systemctl enable vault
systemctl start vault
