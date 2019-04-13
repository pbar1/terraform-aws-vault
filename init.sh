#!/bin/bash

set -e

#--------------------------------------------------------------------
# This script initializes Vault if it has not yet been initialized
# It is meant to be run as a local-exec provisioner from Terraform
#
# Dependencies: jq, vault
#
# Usage: bash init.sh [VAULT_ADDR] [SSM_PATH_VAULT_ROOT_TOKEN] [SSM_PATH_VAULT_RECOVERY_KEY_BASE64]
#--------------------------------------------------------------------

export VAULT_ADDR="$1"
SSM_PATH_VAULT_ROOT_TOKEN="$2"
SSM_PATH_VAULT_RECOVERY_KEY_BASE64="$3"

end=$((SECONDS+300))

while [ $SECONDS -lt $end ]; do
  if [ "$(vault operator init -status)" -eq 2 ]; then
    break
  fi
done

INIT_JSON="$(vault operator init -recovery-shares=1 -recovery-threshold=1 -format=json)"

ROOT_TOKEN=$(echo "$INIT_JSON" | jq -r '.root_token')
RECOVERY_KEY_BASE64=$(echo "$INIT_JSON" | jq -r '.unseal_keys_b64[0]')

aws ssm put-parameter --name "$SSM_PATH_VAULT_ROOT_TOKEN" --value "$ROOT_TOKEN" --type SecureString
aws ssm put-parameter --name "$SSM_PATH_VAULT_RECOVERY_KEY_BASE64" --value "$RECOVERY_KEY_BASE64" --type SecureString
