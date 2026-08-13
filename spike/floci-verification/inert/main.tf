# Question 1: do inert-tier resources actually apply against floci?
# Question 3: does EKS mock mode cover enough that no Docker socket is needed?
#
# One resource of each kind the roadmap names, and no more. This is a probe,
# not a design — see ../README.md.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Deliberately wide. Pinning is for the reference design, where a
      # provider upgrade should be a decision; here it would only add a
      # reason for the run to fail that has nothing to do with the questions.
      version = ">= 5.0, < 7.0"
    }
  }
}

variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://localhost:4566"
}

# Everything about this provider block says "not real AWS": fake static
# credentials, every credential and metadata check skipped, and one endpoint
# for all services. floci answers the whole AWS API surface on a single port.
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    cloudfront = var.endpoint
    ec2        = var.endpoint
    eks        = var.endpoint
    elbv2      = var.endpoint
    iam        = var.endpoint
    sts        = var.endpoint
    wafv2      = var.endpoint
  }
}

locals {
  name = "spike"

  tags = {
    Spike     = "floci-verification"
    Throwaway = "true"
  }
}

# --- Network -----------------------------------------------------------------
#
# Present only because a load balancer and a node group cannot exist without
# one. Two subnets in different availability zones because that is an ALB's
# minimum.

resource "aws_vpc" "spike" {
  cidr_block = "10.42.0.0/16"
  tags       = local.tags
}

resource "aws_subnet" "spike" {
  count = 2

  vpc_id            = aws_vpc.spike.id
  cidr_block        = "10.42.${count.index}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"
  tags              = local.tags
}

resource "aws_security_group" "spike" {
  name   = "${local.name}-sg"
  vpc_id = aws_vpc.spike.id
  tags   = local.tags
}

# --- Inert tier --------------------------------------------------------------
#
# The three the roadmap names by name. None of these will carry traffic on the
# emulator; the question is only whether the API accepts them.

resource "aws_lb" "spike" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  subnets            = aws_subnet.spike[*].id
  security_groups    = [aws_security_group.spike.id]
  tags               = local.tags
}

resource "aws_cloudfront_distribution" "spike" {
  enabled = true

  origin {
    origin_id   = "spike-origin"
    domain_name = aws_lb.spike.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "spike-origin"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

# REGIONAL rather than CLOUDFRONT scope: the question is whether a Web ACL
# applies at all, and CLOUDFRONT scope adds a us-east-1 constraint that would
# only give the run another way to fail for reasons unrelated to it.
resource "aws_wafv2_web_acl" "spike" {
  name  = "${local.name}-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${local.name}-acl"
    sampled_requests_enabled   = false
  }

  tags = local.tags
}

# --- EKS, and the node group's companions ------------------------------------
#
# This is the pair of questions the run is really for. The cluster and node
# group answer question 3: the job mounts no Docker socket and runs floci with
# FLOCI_SERVICES_EKS_MOCK=true, so if these apply, the CI gate does not need
# the socket. The launch template and placement group are question 1's
# remaining two resources.

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-node"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_eks_cluster" "spike" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = aws_subnet.spike[*].id
  }

  tags = local.tags
}

resource "aws_launch_template" "spike" {
  name          = "${local.name}-lt"
  instance_type = "t3.small"
  tags          = local.tags
}

resource "aws_placement_group" "spike" {
  name     = "${local.name}-pg"
  strategy = "spread"
  tags     = local.tags
}

resource "aws_eks_node_group" "spike" {
  cluster_name    = aws_eks_cluster.spike.name
  node_group_name = "${local.name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.spike[*].id

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  tags = local.tags
}

# --- What the run should report ----------------------------------------------

output "applied" {
  description = "The inert-tier resources floci accepted, with the identifiers it returned."

  value = {
    alb             = aws_lb.spike.arn
    cloudfront      = aws_cloudfront_distribution.spike.id
    waf_web_acl     = aws_wafv2_web_acl.spike.id
    eks_cluster     = aws_eks_cluster.spike.arn
    eks_node_group  = aws_eks_node_group.spike.id
    launch_template = aws_launch_template.spike.id
    placement_group = aws_placement_group.spike.id
  }
}

# An identifier proves the API answered. It does not prove anything works —
# that distinction is the whole reason the inert tier gets labelled, and this
# output exists to be read with it in mind.
output "caveat" {
  description = "What the output above does and does not mean."
  value       = "Identifiers mean the API accepted the resource, not that it does anything."
}
