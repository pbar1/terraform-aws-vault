data "aws_region" "current" {
}

data "aws_caller_identity" "current" {
}

data "aws_kms_key" "ssm" {
  key_id = "alias/aws/ssm"
}

# KMS

resource "aws_kms_key" "vault" {
  description = "${var.cluster_name} key for S3 storage backend, Auto Unseal, and SSM Parameter Store"
  tags        = var.tags
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.cluster_name}"
  target_key_id = aws_kms_key.vault.key_id
}

# S3

resource "aws_s3_bucket" "vault" {
  bucket_prefix = "${var.cluster_name}-storage-"
  acl           = "private"
  force_destroy = false

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.vault.key_id
      }
    }
  }

  tags = var.tags
}

resource "aws_s3_bucket_policy" "vault" {
  bucket = aws_s3_bucket.vault.id
  policy = data.aws_iam_policy_document.vault_bucket_policy.json
}

data "aws_iam_policy_document" "vault_bucket_policy" {
  statement {
    sid    = "AllowVaultRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.vault.arn]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.vault.arn,
      "${aws_s3_bucket.vault.arn}/*",
    ]
  }
}

# DynamoDB

resource "aws_dynamodb_table" "vault" {
  name           = "${var.cluster_name}-ha"
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

  tags = var.tags
}

# IAM

data "aws_iam_policy_document" "vault_role_policy" {
  statement {
    sid    = "DynamoHABackend"
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
    sid    = "KMSAutoUnseal"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [
      aws_kms_key.vault.arn,
      data.aws_kms_key.ssm.arn,
    ]
  }

  statement {
    sid     = "SSMParameters"
    effect  = "Allow"
    actions = ["ssm:GetParameter"]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/vault/${var.cluster_name}/*",
    ]
  }
}

resource "aws_iam_policy" "vault" {
  name        = var.cluster_name
  description = "DynamoDB, KMS, and SSM access for Vault cluster ${var.cluster_name}"
  policy      = data.aws_iam_policy_document.vault_role_policy.json
}

resource "aws_iam_role_policy_attachment" "vault" {
  role       = aws_iam_role.vault.name
  policy_arn = aws_iam_policy.vault.arn
}

resource "aws_iam_role" "vault" {
  name               = var.cluster_name
  description        = "Role that Vault cluster ${var.cluster_name} runs as"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = var.tags
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
  name = var.cluster_name
  role = aws_iam_role.vault.name
}

# SG

resource "aws_security_group" "vault_cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "Vault cluster ${var.cluster_name} internal communication"
  vpc_id      = var.vpc_id

  ingress {
    description = "Vault UI and API connectivity"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Vault server to server traffic within a cluster"
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Vault client security group"
    from_port       = 8200
    to_port         = 8200
    protocol        = "tcp"
    security_groups = [aws_security_group.vault_client.id]
  }

  egress {
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_security_group" "vault_client" {
  name        = "${var.cluster_name}-client"
  description = "Vault cluster ${var.cluster_name} clients"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

# ASG

data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")

  vars = {
    aws_region         = data.aws_region.current.name
    vault_cluster_name = var.cluster_name
    s3_bucket          = aws_s3_bucket.vault.id
    kms_key_id         = aws_kms_key.vault.key_id
    dynamodb_table     = aws_dynamodb_table.vault.name
  }
}

resource "aws_launch_template" "vault" {
  name                   = var.cluster_name
  description            = "Vault cluster ${var.cluster_name} launch template"
  image_id               = var.ami_id
  user_data              = base64encode(data.template_file.user_data.rendered)
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.vault_cluster.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.vault.arn
  }

  # tag_specifications {
  #   resource_type = "instance"
  #   tags          = "${var.tags}"
  # }

  tags = var.tags
}

resource "aws_autoscaling_group" "vault" {
  name                = var.cluster_name
  min_size            = var.min_instances
  max_size            = var.max_instances
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.vault.arn]

  launch_template {
    id      = aws_launch_template.vault.id
    version = aws_launch_template.vault.latest_version
  }
}

# LB

resource "aws_lb_target_group" "vault" {
  name     = var.cluster_name
  port     = 8200
  protocol = "TCP"
  vpc_id   = var.vpc_id

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = aws_lb.vault.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vault.arn
  }
}

resource "aws_lb" "vault" {
  name                       = var.cluster_name
  internal                   = var.internal_lb
  load_balancer_type         = "network"
  enable_deletion_protection = var.enable_termination_protection
  subnets                    = var.subnet_ids
  tags                       = var.tags
}

# Route 53

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

