# Terraform Module: Hashicorp Vault on AWS

Hashicorp Vault with KMS Auto Unseal, S3 storage, and DynamoDB high availability.

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

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|:----:|:-----:|:-----:|
| ami\_id | AMI ID to launch the Vault auto scaling group with | string | n/a | yes |
| cluster\_name | Name of the Vault cluster | string | `"vault"` | no |
| dogstatsd\_tags | List of tags to attach to DogStatsD metrics. Written as a raw HCL string | string | `"[\"vault_cluster:vault\"]\n"` | no |
| domain\_name | Domain name of DNS entry to create | string | n/a | yes |
| dynamodb\_read\_capacity | Read capacity for Vault's DynamoDB high availability backend | string | `"5"` | no |
| dynamodb\_write\_capacity | Write capacity for Vault's DynamoDB high availability backend | string | `"5"` | no |
| enable\_cross\_zone\_load\_balancing | Enable cross zone load balancing | string | `"true"` | no |
| enable\_s3\_force\_destroy | Enable to allow Terraform to destroy the S3 bucket even if it is not empty | string | `"false"` | no |
| enable\_termination\_protection | Enable EC2 instance termination protection | string | `"true"` | no |
| extra\_cidr\_blocks | List of CIDR blocks allowed to access the Vault API. The VPC in which Vault resides is already covered. | list | `[]` | no |
| instance\_type | EC2 instance type for Vault instances | string | `"t2.medium"` | no |
| internal\_lb | Whether to make the Vault load balancer internal | string | `"true"` | no |
| max\_instances | Maximum number of Vault instances in the auto scaling group | string | `"3"` | no |
| min\_instances | Minimum number of Vault instances in the auto scaling group | string | `"3"` | no |
| ssh\_key\_name | Name of the SSH keypair to use for the Vault EC2 instances | string | n/a | yes |
| ssm\_path\_datadog\_api\_key | Path to a Datadog API key in the SSM Parameter Store | string | `"/vault/datadog_api_key"` | no |
| ssm\_path\_vault\_cert | Path to the Vault TLS certificate in the SSM Parameter Store | string | `"/vault/vault.pem"` | no |
| ssm\_path\_vault\_intermediate | Path to the Vault TLS intermediate certificate in the SSM Parameter Store | string | `"/vault/vault-intermediate.pem"` | no |
| ssm\_path\_vault\_key | Path to the Vault TLS private key in the SSM Parameter Store | string | `"/vault/vault-key.pem"` | no |
| ssm\_path\_vault\_recovery\_key\_base64 | Path to store the base64-encoded Vault recovery key in the SSM Parameter Store upon init | string | `"/vault/recovery_key_base64"` | no |
| ssm\_path\_vault\_root\_token | Path to store the Vault root token in the SSM Parameter Store upon init | string | `"/vault/root_token"` | no |
| subnet\_ids | List of subnet IDs to launch the Vault auto scaling group in | list | n/a | yes |
| tags | Extra tags to add to all resources created by this module | map | `{}` | no |
| vpc\_id | ID of the AWS VPC to create the Vault cluster in | string | n/a | yes |
| zone\_id | Route53 hosted zone ID to create the DNS entry in | string | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| kms\_key\_id | ID of the KMS key that Vault uses for Auto-Unseal, S3 encryption, and SSM parameters |
| vault\_cluster\_fqdn | Fully qualified domain name for the Vault cluster |
| vault\_cluster\_role\_arn | ARN of the AWS IAM role that Vault runs as |
| vault\_cluster\_role\_name | Name of the AWS IAM role that Vault runs as |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
