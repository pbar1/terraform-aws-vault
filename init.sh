#!/bin/bash

set -e

#--------------------------------------------------------------------
# This script initializes Vault if it has not yet been initialized
# It is meant to be run as a local-exec provisioner from Terraform
#
# Dependencies: vault, jq
#
# Usage: bash init.sh [VAULT_ADDR] [SSM_PATH_VAULT_ROOT_TOKEN] [SSM_PATH_VAULT_RECOVERY_KEYS_B64]
#--------------------------------------------------------------------

export VAULT_ADDR="$1"

SSM_PATH_VAULT_ROOT_TOKEN="$2"
SSM_PATH_VAULT_RECOVERY_KEYS_B64="$3"

export AWS_DEFAULT_REGION="$4"

end=$((SECONDS+900))

set +e
while [[ $SECONDS -lt $end ]]; do
  init_status=$(curl ${VAULT_ADDR}/v1/sys/init | jq .initialized)
  if [[ ${init_status} == "false" ]]; then
    break
  fi
  sleep 30
done
set -e

if [[ ${init_status} != "false" ]]; then
    echo "Vault is not ready to be initialized after 900 seconds"
    exit 1
fi

INIT_JSON="$(curl ${VAULT_ADDR}/v1/sys/init -X PUT -d '{"recovery_shares": 1, "recovery_threshold": 1}')"

ROOT_TOKEN=$(echo "$INIT_JSON" | jq -r '.root_token')
RECOVERY_KEYS_B64=$(echo "$INIT_JSON" | jq -r '.recovery_keys_base64[]')

aws ssm put-parameter --name "$SSM_PATH_VAULT_ROOT_TOKEN" --value "$ROOT_TOKEN" --type SecureString
aws ssm put-parameter --name "$SSM_PATH_VAULT_RECOVERY_KEYS_B64" --value "$RECOVERY_KEYS_B64" --type SecureString