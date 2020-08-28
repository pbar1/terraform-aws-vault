output "name" {
  description = "Name of resources created by this module"
  value       = "${module.nametagger.name}"
}

output "tags" {
  description = "Tags applied to AWS resources created by this module"
  value       = "${module.nametagger.tags}"
}

output "url" {
  description = "URL to reach the Vault cluster at"
  value       = "https://${aws_route53_record.vault.fqdn}"
}

output "role_arn" {
  description = "ARN of the AWS IAM role that Vault runs as"
  value       = "${aws_iam_role.vault.arn}"
}

output "role_name" {
  description = "Name of the AWS IAM role that Vault runs as"
  value       = "${aws_iam_role.vault.name}"
}

output "kms_key_id" {
  description = "ID of the KMS key that Vault uses for Auto Unseal"
  value       = "${aws_kms_key.vault.key_id}"
}

output "ami_name" {
  description = "Name of the AMI used to launch the auto scaling group"
  value       = "${data.aws_ami.vault.name}"
}

output "ami_id" {
  description = "ID of the AMI used to launch the auto scaling group"
  value       = "${data.aws_ami.vault.id}"
}

output "ssm_path_vault_root_token" {
  description = "Path in SSM Parameter Store to Vault root token"
  value       = "${local.ssm_path_vault_root_token}"
}

output "ssm_path_vault_recovery_keys_b64" {
  description = "Path in SSM Parameter Store to Vault recovery keys in base64 format"
  value       = "${local.ssm_path_vault_recovery_keys_b64}"
}
