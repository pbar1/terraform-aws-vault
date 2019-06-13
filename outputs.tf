output "vault_cluster_fqdn" {
  description = "Fully qualified domain name for the Vault cluster"
  value       = aws_route53_record.vault.fqdn
}

output "vault_client_sg_id" {
  description = "ID of the security group used by clients to connect to Vault"
  value       = aws_security_group.vault_client.id
}

output "vault_cluster_role_arn" {
  description = "ARN of the AWS IAM role that Vault runs as"
  value       = aws_iam_role.vault.arn
}

output "vault_cluster_role_name" {
  description = "Name of the AWS IAM role that Vault runs as"
  value       = aws_iam_role.vault.name
}

output "kms_key_id" {
  description = "ID of the KMS key that Vault uses for Auto-Unseal, S3 encryption, and SSM parameters"
  value       = aws_kms_key.vault.key_id
}

