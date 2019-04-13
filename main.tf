#--------------------------------------------------------------------
# Local Variables
#--------------------------------------------------------------------

locals {
  tags = "${merge(
    var.tags,
    map("ManagedBy", "Terraform"),
    map("Name", var.cluster_name),
  )}"

  # Assumes the SSM Parameters are in the same account and region as Vault
  ssm_arn_base = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter"
}

#--------------------------------------------------------------------
# Data Providers
#--------------------------------------------------------------------

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "current" {
  id = "${var.vpc_id}"
}

data "aws_kms_key" "ssm" {
  key_id = "alias/aws/ssm"
}

#--------------------------------------------------------------------
# Resources - KMS (for Vault Auto-Unseal)
#--------------------------------------------------------------------

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.cluster_name}"
  target_key_id = "${aws_kms_key.vault.key_id}"
}

resource "aws_kms_key" "vault" {
  tags        = "${local.tags}"
  description = "${var.cluster_name} key for Vault S3 storage backend and Auto Unseal"
}

#--------------------------------------------------------------------
# Resources - S3 (for Vault Storage backend)
#--------------------------------------------------------------------

resource "aws_s3_bucket" "vault" {
  tags          = "${local.tags}"
  bucket_prefix = "${var.cluster_name}-storage-"
  acl           = "private"
  force_destroy = "${var.enable_s3_force_destroy}"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "${aws_kms_key.vault.key_id}"
      }
    }
  }
}

resource "aws_s3_bucket_policy" "vault" {
  bucket = "${aws_s3_bucket.vault.id}"
  policy = "${data.aws_iam_policy_document.vault_bucket_policy.json}"
}

data "aws_iam_policy_document" "vault_bucket_policy" {
  statement {
    sid    = "VaultStorageDeny"
    effect = "Deny"

    not_principals {
      type = "AWS"

      identifiers = [
        "${aws_iam_role.vault.arn}",
        "${data.aws_caller_identity.current.arn}",
      ]
    }

    actions = ["s3:*"]

    resources = [
      "${aws_s3_bucket.vault.arn}",
      "${aws_s3_bucket.vault.arn}/*",
    ]
  }
}

#--------------------------------------------------------------------
# Resources - DynamoDB (for Vault HA backend)
#--------------------------------------------------------------------

resource "aws_dynamodb_table" "vault" {
  tags           = "${local.tags}"
  name           = "${var.cluster_name}-ha"
  read_capacity  = "${var.dynamodb_read_capacity}"
  write_capacity = "${var.dynamodb_write_capacity}"
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
}

#--------------------------------------------------------------------
# Resources - IAM
#--------------------------------------------------------------------

data "aws_iam_policy_document" "vault_role_policy" {
  statement {
    sid     = "VaultStorage"
    effect  = "Allow"
    actions = ["s3:*"]

    resources = [
      "${aws_s3_bucket.vault.arn}",
      "${aws_s3_bucket.vault.arn}/*",
    ]
  }

  statement {
    sid    = "VaultHA"
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

    resources = ["${aws_dynamodb_table.vault.arn}"]
  }

  statement {
    sid       = "VaultAutoUnseal"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["${aws_kms_key.vault.arn}"]
  }

  statement {
    sid    = "VaultSSMKMS"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [
      "${data.aws_kms_key.ssm.arn}",
    ]
  }

  statement {
    sid    = "VaultSSMParameters"
    effect = "Allow"

    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]

    resources = [
      "${local.ssm_arn_base}${var.ssm_path_datadog_api_key}",
      "${local.ssm_arn_base}${var.ssm_path_vault_cert}",
      "${local.ssm_arn_base}${var.ssm_path_vault_key}",
      "${local.ssm_arn_base}${var.ssm_path_vault_intermediate}",
      "${local.ssm_arn_base}${var.ssm_path_vault_root_token}",
      "${local.ssm_arn_base}${var.ssm_path_vault_recovery_key_base64}",
    ]
  }
}

resource "aws_iam_policy" "vault" {
  name        = "${var.cluster_name}"
  description = "S3, DynamoDB, KMS, and SSM access for Vault cluster ${var.cluster_name}"
  policy      = "${data.aws_iam_policy_document.vault_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "vault" {
  role       = "${aws_iam_role.vault.name}"
  policy_arn = "${aws_iam_policy.vault.arn}"
}

resource "aws_iam_role" "vault" {
  tags               = "${local.tags}"
  name               = "${var.cluster_name}"
  description        = "Vault cluster ${var.cluster_name}"
  assume_role_policy = "${data.aws_iam_policy_document.assume_ec2.json}"
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
  name = "${var.cluster_name}"
  role = "${aws_iam_role.vault.name}"
}

#--------------------------------------------------------------------
# Resources - Security Group
#--------------------------------------------------------------------

resource "aws_security_group" "vault_cluster" {
  tags        = "${local.tags}"
  name        = "${var.cluster_name}"
  description = "Vault cluster ${var.cluster_name}"
  vpc_id      = "${var.vpc_id}"

  ingress {
    description = "Vault UI and API"
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    self        = true
    cidr_blocks = ["${concat(list(data.aws_vpc.current.cidr_block), var.extra_cidr_blocks)}"]
  }

  ingress {
    description = "Vault server to server"
    from_port   = 8201
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

data "template_file" "user_data" {
  template = "${file("${path.module}/userdata.sh")}"

  vars = {
    cluster_name   = "${var.cluster_name}"
    aws_region     = "${data.aws_region.current.name}"
    s3_bucket      = "${aws_s3_bucket.vault.id}"
    kms_key_id     = "${aws_kms_key.vault.key_id}"
    dynamodb_table = "${aws_dynamodb_table.vault.name}"
    dogstatsd_tags = "${var.dogstatsd_tags}"

    ssm_path_datadog_api_key    = "${var.ssm_path_datadog_api_key}"
    ssm_path_vault_cert         = "${var.ssm_path_vault_cert}"
    ssm_path_vault_key          = "${var.ssm_path_vault_key}"
    ssm_path_vault_intermediate = "${var.ssm_path_vault_intermediate}"
  }
}

resource "aws_launch_template" "vault" {
  tags                   = "${local.tags}"
  name                   = "${var.cluster_name}"
  description            = "Vault cluster ${var.cluster_name}"
  image_id               = "${var.ami_id}"
  user_data              = "${base64encode(data.template_file.user_data.rendered)}"
  instance_type          = "${var.instance_type}"
  key_name               = "${var.ssh_key_name}"
  vpc_security_group_ids = ["${aws_security_group.vault_cluster.id}"]

  iam_instance_profile {
    arn = "${aws_iam_instance_profile.vault.arn}"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = "${local.tags}"
  }
}

resource "aws_autoscaling_group" "vault" {
  name                      = "${var.cluster_name}"
  min_size                  = "${var.min_instances}"
  max_size                  = "${var.max_instances}"
  vpc_zone_identifier       = ["${var.subnet_ids}"]
  target_group_arns         = ["${aws_lb_target_group.vault.arn}"]
  min_elb_capacity          = 1
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = "${aws_launch_template.vault.id}"
    version = "${aws_launch_template.vault.latest_version}"
  }

  provisioner "local-exec" {
    command = "bash init.sh '${var.ssm_path_vault_root_token}' '${var.ssm_path_vault_recovery_key_base64}'"

    environment = {
      VAULT_ADDR = "https://${var.domain_name}"
    }
  }
}

#--------------------------------------------------------------------
# Resources - Network Load Balancer
#--------------------------------------------------------------------

resource "aws_lb_target_group" "vault" {
  tags     = "${local.tags}"
  name     = "${var.cluster_name}"
  port     = 8200
  protocol = "TCP"
  vpc_id   = "${var.vpc_id}"

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "vault" {
  load_balancer_arn = "${aws_lb.vault.arn}"
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.vault.arn}"
  }
}

resource "aws_lb" "vault" {
  tags               = "${local.tags}"
  name               = "${var.cluster_name}"
  internal           = "${var.internal_lb}"
  load_balancer_type = "network"
  subnets            = ["${var.subnet_ids}"]

  enable_deletion_protection       = "${var.enable_termination_protection}"
  enable_cross_zone_load_balancing = "${var.enable_cross_zone_load_balancing}"
}

#--------------------------------------------------------------------
# Resources - Route53
#--------------------------------------------------------------------

resource "aws_route53_record" "vault" {
  zone_id = "${var.zone_id}"
  name    = "${var.domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_lb.vault.dns_name}"
    zone_id                = "${aws_lb.vault.zone_id}"
    evaluate_target_health = false
  }
}
