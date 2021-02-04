package test

import (
	"crypto/rand"
	"fmt"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"net/http"
	"testing"
	"time"
)

func TestVault(t *testing.T) {
	r := make([]byte, 3)
	_, err := rand.Read(r)
	if err != nil {
		t.Errorf("failed to generate random number: %s", err.Error())
	}

	environment := fmt.Sprintf("terratest%x", r)
	domain := fmt.Sprintf("%s.example.com", environment)

	expectedURL := "https://" + domain
	expectedSSMPathVaultRecoveryKeysB64 := fmt.Sprintf("/terratest/recovery_keys_b64")
	expectedSSMPathVaultRootToken := fmt.Sprintf("/terratest/root_token")

	terraformOptions := &terraform.Options{
		TerraformDir: "../",
		VarFiles:     []string{"test/test.tfvars"},
		Vars: map[string]interface{}{
			"environment": environment,
			"domain_name": domain,
		},
		NoColor: true,
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	actualURL := terraform.Output(t, terraformOptions, "url")
	actualSSMPathVaultRecoveryKeysB64 := terraform.Output(t, terraformOptions, "ssm_path_vault_recovery_keys_b64")
	actualSSMPathVaultRootToken := terraform.Output(t, terraformOptions, "ssm_path_vault_root_token")

	assert.Equal(t, expectedURL, actualURL)
	assert.Equal(t, expectedSSMPathVaultRecoveryKeysB64, actualSSMPathVaultRecoveryKeysB64)
	assert.Equal(t, expectedSSMPathVaultRootToken, actualSSMPathVaultRootToken)

	assert.True(t, vaultIsHealthy(t, actualURL), "Expected vault endpoint to become healthy, but it didn't")
}

func vaultIsHealthy(t *testing.T, vaultURL string) bool {
	timeoutInterval := 60 * time.Second
	pollingInterval := 10 * time.Second
	timeout := time.After(timeoutInterval)

	logger.Log(t, "Waiting for vault to become healthy...")
	for {
		select {
		case <-time.After(pollingInterval):
			if resp, err := http.Get(fmt.Sprintf("%s/v1/sys/health", vaultURL)); err == nil {
				logger.Log(t, "received status code: ", resp.StatusCode)
				if resp.StatusCode == http.StatusOK {
					logger.Log(t, "Vault is healthy!")
					return true
				}
			}
		case <-timeout:
			logger.Log(t, "Vault is unhealthy.")
			return false
		}
	}
}
