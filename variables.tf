#--------------------------------------------------------------------
# Required Variables
#--------------------------------------------------------------------

variable "environment" {
  description = "Environment name - valid values are `build`, `dev`, `staging`, and `prod`"
}

variable "region" {
  description = "AWS region name, in the form of `us-west-2` and `eu-central-1`"
}

variable "name" {
  description = "Name of the app, service, etc. For example: `vault` or `terraform`. No environment or region information, the module will take care of naming for you."
}

variable "vault_version" {
  description = "Version of Vault to deploy. Will search for a privately-owned AMI that satisfies the condition."
}

variable "ssh_key_name" {
  description = "Name of the SSH keypair to use for the Vault EC2 instances"
}

variable "vpc_id" {
  description = "ID of the AWS VPC to create the Vault cluster in"
}

variable "subnet_ids" {
  description = "List of subnet IDs to launch the Vault auto scaling group in"
  type        = list
}

variable "zone_id" {
  description = "Route53 hosted zone ID to create the DNS entry in (should probably be private)"
}

variable "domain_name" {
  description = "Domain name of DNS entry to create"
}

variable "ssm_path_datadog_api_key" {
  description = "Path to the Datadog API key in SSM Parameter Store (Expected to be of type `SecureString`, encrypted by the default SSM KMS key)"
}

variable "ssm_path_sumologic_access_id" {
  description = "Path to the Sumo Logic Access ID in SSM Parameter Store (Expected to be of type `String`)"
}

variable "ssm_path_sumologic_access_key" {
  description = "Path to the Sumo Logic Access Key in SSM Parameter Store (Expected to be of type `SecureString`, encrypted by the default SSM KMS key)"
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate to be used by the ALB."
}

variable "ami_account_ids" {
  description = "List of AWS account IDs to use when filtering for the Vault AMI"
}

#--------------------------------------------------------------------
# Optional Variables
#--------------------------------------------------------------------

variable "tags" {
  description = "Extra tags to add to all resources created by this module"
  type        = map
  default     = {}
}

variable "dogstatsd_tags" {
  description = "List of tags to attach to DogStatsD metrics. Written as a raw HCL string"
  type        = string

  default = <<HCL
["vault_cluster:vault"]
HCL
}

variable "instance_type" {
  description = "EC2 instance type for Vault instances"
  default     = "r5.large"
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
  description = "Write capacity for Vault's DynamoDB storgage backend"
  default     = 5
}

variable "dynamodb_read_capacity" {
  description = "Read capacity for Vault's DynamoDB storgage backend"
  default     = 5
}

variable "dynamodb_write_capacity_max" {
  description = "Max write capacity for Vault's DynamoDB storgage backend"
  default     = 20
}

variable "dynamodb_read_capacity_max" {
  description = "Max read capacity for Vault's DynamoDB storgage backend"
  default     = 20
}

variable "dynamodb_write_scale_target" {
  description = "Percentage of current DynamoDB write capacity at which auto scaling triggers"
  default     = 50
}

variable "dynamodb_read_scale_target" {
  description = "Percentage of current DynamoDB read capacity at which auto scaling triggers"
  default     = 50
}

variable "internal_lb" {
  description = "Whether to make the Vault load balancer internal"
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross zone load balancing"
  default     = true
}

variable "extra_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the Vault API. The VPC in which Vault resides is already covered."
  type        = list
  default     = []
}

variable "allowed_security_groups" {
  description = "List of security groups allowed to access the Vault API."
  type        = list
  default     = []
}

variable "ssm_path_vault_recovery_keys_b64" {
  description = "Path to store the Vault recovery keys (in base64) in SSM Parameter Store upon initialization"
  default     = ""
}

variable "ssm_path_vault_root_token" {
  description = "Path to store the Vault root token in SSM Parameter Store upon initialization"
  default     = ""
}

variable "ebs_root_volume_device_name" {
  description = "The location in which the root volume is mounted. Defaults to `/dev/xvda`, which is where Amazon Linux 2 mounts its root volume."
  default     = "/dev/xvda"
}

variable "acm_pca_arn" { 
  type = string
  description = "Arn of the ACM Private CA you want to sign the cert request"
  default = ""
}
variable "ebs_root_volume_type" {
  default = "gp2"
}

variable "ebs_root_volume_size" {
  default = 30
}

variable "ebs_root_volume_delete_on_termination" {
  default = true
}

variable "ebs_root_volume_encrypted" {
  default = true
}

variable "spot" {
  default = false
}

variable "init_cluster" {
  type = bool
  default = "true"
  description = "If set to true, the cluster will init with a local provisioner and store root token and unseal keys in SSM Parameter store."
}