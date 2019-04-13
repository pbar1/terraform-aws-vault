#!/bin/bash

set -e

#--------------------------------------------------------------------
# This script initializes Vault if it has not yet been initialized
# It is meant to be run as a local-exec provisioner from Terraform
#
# Dependencies: vault, jq
#
# Usage: bash init.sh [SSM_PATH_VAULT_ROOT_TOKEN] [SSM_PATH_VAULT_RECOVERY_KEY_BASE64]
#--------------------------------------------------------------------

SSM_PATH_VAULT_ROOT_TOKEN="$1"
SSM_PATH_VAULT_RECOVERY_KEY_BASE64="$2"

end=$((SECONDS+300))

set +e
while [ $SECONDS -lt $end ]; do
  vault operator init -status
  if [ $? -eq 2 ]; then
    break
  fi
  sleep 30
done
set -e

INIT_JSON="$(vault operator init -recovery-shares=1 -recovery-threshold=1 -format=json)"

ROOT_TOKEN=$(echo "$INIT_JSON" | jq -r '.root_token')
RECOVERY_KEY_BASE64=$(echo "$INIT_JSON" | jq -r '.keys_base64[0]')

aws ssm put-parameter --name "$SSM_PATH_VAULT_ROOT_TOKEN" --value "$ROOT_TOKEN" --type SecureString
aws ssm put-parameter --name "$SSM_PATH_VAULT_RECOVERY_KEY_BASE64" --value "$RECOVERY_KEY_BASE64" --type SecureString
