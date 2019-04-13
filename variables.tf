#--------------------------------------------------------------------
# Required Variables
#--------------------------------------------------------------------

variable "ami_id" {
  description = "AMI ID to launch the Vault auto scaling group with"
}

variable "ssh_key_name" {
  description = "Name of the SSH keypair to use for the Vault EC2 instances"
}

variable "vpc_id" {
  description = "ID of the AWS VPC to create the Vault cluster in"
}

variable "subnet_ids" {
  description = "List of subnet IDs to launch the Vault auto scaling group in"
  type        = "list"
}

variable "zone_id" {
  description = "Route53 hosted zone ID to create the DNS entry in"
}

variable "domain_name" {
  description = "Domain name of DNS entry to create"
}

#--------------------------------------------------------------------
# Optional Variables
#--------------------------------------------------------------------

variable "tags" {
  description = "Extra tags to add to all resources created by this module"
  type        = "map"
  default     = {}
}

variable "cluster_name" {
  description = "Name of the Vault cluster"
  default     = "vault"
}

variable "dogstatsd_tags" {
  description = "List of tags to attach to DogStatsD metrics. Written as a raw HCL string"
  type        = "string"

  default = <<HCL
["vault_cluster:vault"]
HCL
}

variable "instance_type" {
  description = "EC2 instance type for Vault instances"
  default     = "t2.medium"
}

variable "min_instances" {
  description = "Minimum number of Vault instances in the auto scaling group"
  default     = 3
}

variable "max_instances" {
  description = "Maximum number of Vault instances in the auto scaling group"
  default     = 3
}

variable "enable_termination_protection" {
  description = "Enable EC2 instance termination protection"
  default     = true
}

variable "dynamodb_write_capacity" {
  description = "Write capacity for Vault's DynamoDB high availability backend"
  default     = 5
}

variable "dynamodb_read_capacity" {
  description = "Read capacity for Vault's DynamoDB high availability backend"
  default     = 5
}

variable "internal_lb" {
  description = "Whether to make the Vault load balancer internal"
  default     = true
}

variable "enable_s3_force_destroy" {
  description = "Enable to allow Terraform to destroy the S3 bucket even if it is not empty"
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross zone load balancing"
  default     = true
}

variable "extra_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the Vault API. The VPC in which Vault resides is already covered."
  type        = "list"
  default     = []
}

variable "ssm_path_datadog_api_key" {
  description = "Path to a Datadog API key in the SSM Parameter Store"
  default     = "/vault/datadog_api_key"
}

variable "ssm_path_vault_cert" {
  description = "Path to the Vault TLS certificate in the SSM Parameter Store"
  default     = "/vault/vault.pem"
}

variable "ssm_path_vault_key" {
  description = "Path to the Vault TLS private key in the SSM Parameter Store"
  default     = "/vault/vault-key.pem"
}

variable "ssm_path_vault_intermediate" {
  description = "Path to the Vault TLS intermediate certificate in the SSM Parameter Store"
  default     = "/vault/vault-intermediate.pem"
}

variable "ssm_path_vault_root_token" {
  description = "Path to store the Vault root token in the SSM Parameter Store upon init"
  default     = "/vault/root_token"
}

variable "ssm_path_vault_recovery_key_base64" {
  description = "Path to store the base64-encoded Vault recovery key in the SSM Parameter Store upon init"
  default     = "/vault/recovery_key_base64"
}
