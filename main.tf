locals {
  ssm_path_vault_recovery_keys_b64 = var.ssm_path_vault_recovery_keys_b64 != "" ? var.ssm_path_vault_recovery_keys_b64 : "/${var.name}/recovery_keys_b64"
  
  ssm_path_vault_root_token = var.ssm_path_vault_root_token != "" ? var.ssm_path_vault_root_token : "/${var.name}/root_token"
  
}

#--------------------------------------------------------------------
# Data Providers
#--------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_vpc" "current" {
  id = var.vpc_id
}

data "aws_kms_key" "ssm" {
  key_id = "alias/aws/ssm"
}

data "aws_ssm_parameter" "datadog_api_key" {
  name            = var.ssm_path_datadog_api_key
  with_decryption = false
}

data "aws_ssm_parameter" "sumologic_access_id" {
  name = var.ssm_path_sumologic_access_id
}

data "aws_ssm_parameter" "sumologic_access_key" {
  name            = var.ssm_path_sumologic_access_key
  with_decryption = false
}

data "aws_ami" "vault" {
  owners      = var.ami_account_ids
  most_recent = true

  filter {
    name   = "name"
    values = ["vault-${var.vault_version}-*"]
  }
}

#--------------------------------------------------------------------
# Resources - KMS (for Vault Auto Unseal)
#--------------------------------------------------------------------

resource "aws_kms_key" "vault" {
  tags        = var.tags
  description = "${var.name} key for Vault Auto Unseal"
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.vault.key_id
}

#--------------------------------------------------------------------
# Resources - DynamoDB (for Vault Storage backend)
#--------------------------------------------------------------------

resource "aws_dynamodb_table" "vault" {
  tags           = var.tags
  name           = "${var.name}-storage"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "Path"
  range_key      = "Key"

  attribute {
    name = "Path"
    type = "S"
  }

  attribute {
    name = "Key"
    type = "S"
  }

  lifecycle {
    ignore_changes = [read_capacity, write_capacity]
  }
}

module "dynamodb_autoscaler" {
  source  = "cloudposse/dynamodb-autoscaler/aws"
  version = "0.8.0"

  namespace                    = "ep"
  stage                        = var.environment
  name                         = var.name
  dynamodb_table_name          = aws_dynamodb_table.vault.name
  dynamodb_table_arn           = aws_dynamodb_table.vault.arn
  autoscale_write_target       = var.dynamodb_write_scale_target
  autoscale_read_target        = var.dynamodb_read_scale_target
  autoscale_min_read_capacity  = var.dynamodb_read_capacity
  autoscale_max_read_capacity  = var.dynamodb_read_capacity_max
  autoscale_min_write_capacity = var.dynamodb_write_capacity
  autoscale_max_write_capacity = var.dynamodb_write_capacity_max
}

#--------------------------------------------------------------------
# Resources - IAM
#--------------------------------------------------------------------

data "aws_iam_policy_document" "vault_role_policy" {
  statement {
    sid    = "VaultStorage"
    effect = "Allow"

    actions = [
      "dynamodb:DescribeLimits",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:DescribeReservedCapacityOfferings",
      "dynamodb:DescribeReservedCapacity",
      "dynamodb:ListTables",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:CreateTable",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:GetRecords",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
      "dynamodb:DescribeTable",
    ]

    resources = [aws_dynamodb_table.vault.arn]
  }

  statement {
    sid    = "VaultKMS"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]

    resources = [
      aws_kms_key.vault.arn,
      data.aws_kms_key.ssm.arn,
    ]
  }

  statement {
    sid    = "VaultSSM"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]

    resources = [
      data.aws_ssm_parameter.datadog_api_key.arn,
      data.aws_ssm_parameter.sumologic_access_id.arn,
      data.aws_ssm_parameter.sumologic_access_key.arn,
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_vault_recovery_keys_b64}",
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_vault_root_token}",
    ]
  }

  # statement {
  #   sid     = "PCAIssueCert"
  #   effect  = "Allow"
  #   actions = [
  #     "acm-pca:IssueCertificate",
  #     "acm-pca:GetCertificate"
  #   ]

  #   resources = [
  #     "*",
  #   ]
  # }
}

resource "aws_iam_policy" "vault" {
  name        = var.name
  description = "DynamoDB, KMS, and SSM access for Vault cluster ${var.name}"
  policy      = data.aws_iam_policy_document.vault_role_policy.json
}

resource "aws_iam_role_policy_attachment" "vault" {
  role       = aws_iam_role.vault.name
  policy_arn = aws_iam_policy.vault.arn
}

resource "aws_iam_role" "vault" {
  tags               = var.tags
  name               = var.name
  description        = "Role that Vault cluster ${var.name} runs as"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_instance_profile" "vault" {
  name = var.name
  role = aws_iam_role.vault.name
}

#--------------------------------------------------------------------
# Resources - Security Group
#--------------------------------------------------------------------
resource "aws_security_group" "vault_lb" {
  tags        = var.tags
  name        = "${var.name}-lb"
  description = "Vault LoadBalancer ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = concat(list(data.aws_vpc.current.cidr_block), var.extra_cidr_blocks)
  }

  ingress {
    description     = "Allowed security groups"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = var.allowed_security_groups
  }

  egress {
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "vault_cluster" {
  tags        = var.tags
  name        = "${var.name}-server"
  description = "Vault cluster ${var.name}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From Vault LB"
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    security_groups = [aws_security_group.vault_lb.id]
  }

  ingress {
    description = "Vault server to server"
    from_port   = 8200
    to_port     = 8201
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#--------------------------------------------------------------------
# Resources - Auto Scaling Group
#--------------------------------------------------------------------

data "template_file" "userdata" {
  template = file("${path.module}/userdata.sh")

  vars = {
    aws_region         = var.region
    kms_key_id         = aws_kms_key.vault.key_id
    dynamodb_table     = aws_dynamodb_table.vault.name
    acm_pca_arn        = var.acm_pca_arn
    cluster_name             = var.name
    cluster_fqdn             = aws_route53_record.vault.fqdn
    dogstatsd_tags           = var.dogstatsd_tags
    ssm_path_datadog_api_key = var.ssm_path_datadog_api_key
    ssm_path_sumo_access_id  = var.ssm_path_sumologic_access_id
    ssm_path_sumo_access_key = var.ssm_path_sumologic_access_key
  }
}

resource "aws_launch_template" "vault" {
  tags                   = var.tags
  name                   = var.name
  description            = "Vault cluster ${var.name} launch template"
  image_id               = data.aws_ami.vault.id
  user_data              = base64encode(data.template_file.userdata.rendered)
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.vault_cluster.id]
  ebs_optimized          = true

  block_device_mappings {
    device_name = var.ebs_root_volume_device_name

    ebs {
      volume_type           = var.ebs_root_volume_type
      volume_size           = var.ebs_root_volume_size
      delete_on_termination = var.ebs_root_volume_delete_on_termination
      encrypted             = var.ebs_root_volume_encrypted
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.vault.arn
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge({"Name"=var.name},var.tags)
  }
}

resource "aws_autoscaling_group" "vault" {
  name                = var.name
  min_size            = var.min_instances
  max_size            = var.max_instances
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.vault.arn]

  launch_template {
    id      = aws_launch_template.vault.id
    version = aws_launch_template.vault.latest_version
  }

  provisioner "local-exec" {
    command = "if ${var.init_cluster} ; then bash '${path.module}/init.sh' 'https://${aws_route53_record.vault.fqdn}' '${local.ssm_path_vault_root_token}' '${local.ssm_path_vault_recovery_keys_b64}' '${var.region}'; fi"
  }
}

#--------------------------------------------------------------------
# Resources - Load Balancer
#--------------------------------------------------------------------

resource "aws_lb_target_group" "vault" {
  tags     = var.tags
  name     = var.name
  port     = 8200
  protocol = "HTTPS"
  vpc_id   = var.vpc_id

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    protocol = "HTTPS"
    path     = "/v1/sys/health"
    matcher  = "200"
  }
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2019-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.vault.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb" "vault" {
  tags     = var.tags
  name     = var.name
  internal = var.internal_lb
  subnets  = var.subnet_ids

  enable_deletion_protection       = var.enable_termination_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  security_groups = [aws_security_group.vault_lb.id]

  lifecycle {
    ignore_changes = [
      access_logs,
    ]
  }
}

#--------------------------------------------------------------------
# Resources - Route53
#--------------------------------------------------------------------

resource "aws_route53_record" "vault" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.vault.dns_name
    zone_id                = aws_lb.vault.zone_id
    evaluate_target_health = false
  }
}
