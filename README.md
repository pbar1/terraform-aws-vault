# Terraform Module: Hashicorp Vault on AWS

Production-ready Vault in a Terraform module

## Goals

This is a Terraform module for creating a production-grade Hashicorp Vault deployment on AWS. Some stated goals:

- Maximum security
- Minimal unmanaged dependencies, to reduce operational complexity
- Ease of deployment, able to be used out of the box

## Architecture

![Vault Architecture Diagram](assets/architecture.png?raw=true)

Normally, Hashicorp recommends using Consul (another one of their tools) as both the storage and high-availability (HA) backend for Vault. This presents a number of challenges:

- Generating Consul agent certificates and Gossip token
- Deploying Consul in an autoscaling group along with IAM resources
- Bootstrapping Consul's ACL system and backing up the master token
- Keeping Consul single-tenant (to prevent data loss/corruption in Vault)
- Monitoring and logging of Consul itself
- Taking periodic Consul snapshots as backup

In order to reduce operational complexity as much as possible, we instead opt for Amazon S3 for Vault's storage backend and AWS DynamoDB for its HA backend. As these are managed services, we can offload much our SLA onto them and focus on maintaining Vault itself. This also loosens our coupling to Consul and simplifies deployment greatly.

## Usage

**First**, build an AMI using the Packer build definition in this repo. This module searches for the most recent version of this AMI.

```terraform
module "vault" {
  source = "github.com/pbar1/terraform-aws-vault?ref=v2.0.0"

  environment = "test"
  region      = "us-west-2"
  name        = "vault"

  ssh_key_name = "..."
  vpc_id       = "..."
  subnet_ids   = ["...", "...", "..."]
  zone_id      = "..."

  domain_name                 = "vault.example.com"
  acme_registration_email     = "..."
  acme_route53_hosted_zone_id = "..."

  # these must already exist
  ssm_path_datadog_api_key      = "/..." 
  ssm_path_sumologic_access_id  = "/..."
  ssm_path_sumologic_access_key = "/..."

  # these will be created
  ssm_path_vault_recovery_keys_b64 = "/..."
  ssm_path_vault_root_token        = "/..."
}
```

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 0.13 |

## Providers

| Name | Version |
|------|---------|
| aws | n/a |
| template | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allowed\_security\_groups | List of security groups allowed to access the Vault API. | `list` | `[]` | no |
| ami\_account\_ids | List of AWS account IDs to use when filtering for the Vault AMI | `list` | `[]` | no |
| certificate\_arn | ARN of the ACM certificate to be used by the ALB. | `any` | n/a | yes |
| dogstatsd\_tags | List of tags to attach to DogStatsD metrics. Written as a raw HCL string | `string` | `"[\"vault_cluster:vault\"]\n"` | no |
| domain\_name | Domain name of DNS entry to create | `any` | n/a | yes |
| dynamodb\_read\_capacity | Read capacity for Vault's DynamoDB storgage backend | `number` | `5` | no |
| dynamodb\_read\_capacity\_max | Max read capacity for Vault's DynamoDB storgage backend | `number` | `20` | no |
| dynamodb\_read\_scale\_target | Percentage of current DynamoDB read capacity at which auto scaling triggers | `number` | `50` | no |
| dynamodb\_write\_capacity | Write capacity for Vault's DynamoDB storgage backend | `number` | `5` | no |
| dynamodb\_write\_capacity\_max | Max write capacity for Vault's DynamoDB storgage backend | `number` | `20` | no |
| dynamodb\_write\_scale\_target | Percentage of current DynamoDB write capacity at which auto scaling triggers | `number` | `50` | no |
| ebs\_root\_volume\_delete\_on\_termination | n/a | `bool` | `true` | no |
| ebs\_root\_volume\_device\_name | The location in which the root volume is mounted. Defaults to `/dev/xvda`, which is where Amazon Linux 2 mounts its root volume. | `string` | `"/dev/xvda"` | no |
| ebs\_root\_volume\_encrypted | n/a | `bool` | `true` | no |
| ebs\_root\_volume\_size | n/a | `number` | `30` | no |
| ebs\_root\_volume\_type | n/a | `string` | `"gp2"` | no |
| enable\_cross\_zone\_load\_balancing | Enable cross zone load balancing | `bool` | `true` | no |
| enable\_termination\_protection | Enable EC2 instance termination protection | `bool` | `true` | no |
| environment | Environment name - valid values are `build`, `dev`, `staging`, and `prod` | `any` | n/a | yes |
| extra\_cidr\_blocks | List of CIDR blocks allowed to access the Vault API. The VPC in which Vault resides is already covered. | `list` | `[]` | no |
| instance\_type | EC2 instance type for Vault instances | `string` | `"r5.large"` | no |
| internal\_lb | Whether to make the Vault load balancer internal | `bool` | `true` | no |
| max\_instances | Maximum number of Vault instances in the auto scaling group | `number` | `3` | no |
| min\_instances | Minimum number of Vault instances in the auto scaling group | `number` | `3` | no |
| name | Name of the app, service, etc. For example: `vault` or `terraform`. No environment or region information, the module will take care of naming for you. | `any` | n/a | yes |
| region | AWS region name, in the form of `us-west-2` and `eu-central-1` | `any` | n/a | yes |
| spot | n/a | `bool` | `false` | no |
| ssh\_key\_name | Name of the SSH keypair to use for the Vault EC2 instances | `any` | n/a | yes |
| ssm\_path\_datadog\_api\_key | Path to the Datadog API key in SSM Parameter Store (Expected to be of type `SecureString`, encrypted by the default SSM KMS key) | `any` | n/a | yes |
| ssm\_path\_sumologic\_access\_id | Path to the Sumo Logic Access ID in SSM Parameter Store (Expected to be of type `String`) | `any` | n/a | yes |
| ssm\_path\_sumologic\_access\_key | Path to the Sumo Logic Access Key in SSM Parameter Store (Expected to be of type `SecureString`, encrypted by the default SSM KMS key) | `any` | n/a | yes |
| ssm\_path\_vault\_recovery\_keys\_b64 | Path to store the Vault recovery keys (in base64) in SSM Parameter Store upon initialization | `string` | `""` | no |
| ssm\_path\_vault\_root\_token | Path to store the Vault root token in SSM Parameter Store upon initialization | `string` | `""` | no |
| subnet\_ids | List of subnet IDs to launch the Vault auto scaling group in | `list` | n/a | yes |
| tags | Extra tags to add to all resources created by this module | `map` | `{}` | no |
| vault\_version | Version of Vault to deploy. Will search for a privately-owned AMI that satisfies the condition. | `any` | n/a | yes |
| vpc\_id | ID of the AWS VPC to create the Vault cluster in | `any` | n/a | yes |
| zone\_id | Route53 hosted zone ID to create the DNS entry in (should probably be private) | `any` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| ami\_id | ID of the AMI used to launch the auto scaling group |
| ami\_name | Name of the AMI used to launch the auto scaling group |
| kms\_key\_id | ID of the KMS key that Vault uses for Auto Unseal |
| name | Name of resources created by this module |
| role\_arn | ARN of the AWS IAM role that Vault runs as |
| role\_name | Name of the AWS IAM role that Vault runs as |
| ssm\_path\_vault\_recovery\_keys\_b64 | Path in SSM Parameter Store to Vault recovery keys in base64 format |
| ssm\_path\_vault\_root\_token | Path in SSM Parameter Store to Vault root token |
| tags | Tags applied to AWS resources created by this module |
| url | URL to reach the Vault cluster at |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
