variable "cluster_name" {
  description = "Name of the Vault cluster"
  default     = "vault"
}

variable "tags" {
  description = "Extra tags to add to all resources created by this module"
  type        = map(string)
  default     = {}
}

variable "ami_id" {
  description = "AMI ID to launch the Vault auto scaling group with"
}

variable "instance_type" {
  description = "EC2 instance type for Vault instances"
  default     = "t3.medium"
}

variable "min_instances" {
  description = "Minimum number of Vault instances in the auto scaling group"
  default     = 3
}

variable "max_instances" {
  description = "Maximum number of Vault instances in the auto scaling group"
  default     = 3
}

variable "vpc_id" {
  description = "ID of the AWS VPC to create the Vault cluster in"
}

variable "subnet_ids" {
  description = "List of subnet IDs to launch the Vault auto scaling group in"
  type        = list(string)
}

variable "ssh_key_name" {
  description = "Name of the SSH keypair to use for the Vault EC2 instances"
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

variable "zone_id" {
  description = "Route53 hosted zone ID to create the DNS entry in"
}

variable "domain_name" {
  description = "Domain name of DNS entry to create"
}

variable "acm_cert_arn" { 
  description = "Cert ARN for NLB TLS termination"
}

variable "allowed_cidrs" { 
  type = list(string)
  description = "List of CIDRs allowed to access Vault UI and API"
  default = []
}
variable "acm_pca_arn" { 
  type = string
  description = "Arn of the ACM Private CA you want to sign the cert request"
  default = "" 
}
