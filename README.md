# Terraform Module: Hashicorp Vault (AWS)

Production-ready Vault in a Terraform module

## Goals

This is a Terraform module for creating a production-grade Hashicorp Vault deployment on AWS. Some stated goals:

- Maximum security
- Minimal unmanaged dependencies, to reduce operational complexity
- Ease of deployment, able to be used out of the box

## Architecture

![Vault Architecture Diagram](/assets/architecture.png?raw=true)

Normally, Hashicorp recommends using Consul (another one of their tools) as both the storage and high-availability (HA) backend for Vault. This presents a number of challenges:

- Generating Consul agent certificates and Gossip token
- Deploying Consul in an autoscaling group along with IAM resources
- Bootstrapping Consul's ACL system and backing up the master token
- Keeping Consul single-tenant (to prevent data loss/corruption in Vault)
- Monitoring and logging of Consul itself

In order to reduce operational complexity as much as possible, we instead opt for Amazon S3 for Vault's storage backend and AWS DynamoDB for its HA backend. As these are managed services, we can offload much our SLA onto them and focus on maintaining Vault itself. This also loosens our coupling to Consul and simplifies deployment greatly.
