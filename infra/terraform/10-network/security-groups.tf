# Security groups for everything the design puts in these VPCs — load
# balancers, cluster nodes, the database — kept in this layer so every rule is
# reviewable in one place. The layers that create those things attach these
# groups; they do not define their own. Decided 2026-10-01, docs/decisions.md.
#
# Nothing is open to 0.0.0.0/0 unless it has to be. The NLB takes traffic only
# from CloudFront's origin-facing addresses, which is the design's own intent:
# nothing behind the perimeter sees the internet directly. The one rule that has
# to be open — nodes out to the internet on 443 — says why, at the rule.
#
# No custom network ACLs. The subnets keep their VPC's default ACL; a declared
# public ACL would have to admit return traffic from 0.0.0.0/0, and the groups
# below already do the filtering.
#
# Each group starts with no egress: Terraform removes the allow-all rule AWS
# adds to a new group, so everything a group may send is listed here.
#
# Inert: floci records groups and rules and filters nothing.

locals {
  # The app container listens on 80 — Thruster in front of Puma, per the app
  # repository's Dockerfile (EXPOSE 80). TLS ends at the ALB.
  app_port = 80

  security_groups = {
    nlb   = { vpc = "perimeter", description = "NLB: HTTPS from CloudFront in, to the ALB out" }
    alb   = { vpc = "perimeter", description = "ALB: HTTPS from the NLB in, HTTP to app pods out" }
    nodes = { vpc = "application", description = "EKS nodes and pods: HTTP from the ALB in; database, DNS and HTTPS out" }
    rds   = { vpc = "application", description = "PostgreSQL: from cluster nodes only, nothing out" }
  }
}

# CloudFront's origin-facing addresses, as AWS publishes and maintains them —
# see the variable for how the emulator gets a stand-in.
data "aws_ec2_managed_prefix_list" "cloudfront_origin" {
  name = var.cloudfront_prefix_list_name
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name        = "${local.name_prefix}-${each.key}"
  description = each.value.description
  vpc_id      = aws_vpc.this[each.value.vpc].id

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-${each.key}"
    Tier = each.value.vpc
  })
}

# --- NLB: the L4 front door --------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "nlb_from_cloudfront" {
  security_group_id = aws_security_group.this["nlb"].id
  description       = "HTTPS from CloudFront's origin-facing addresses only"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin.id
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_alb" {
  security_group_id            = aws_security_group.this["nlb"].id
  description                  = "HTTPS on to the ALB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.this["alb"].id
}

# --- ALB: L7 routing and TLS -------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_from_nlb" {
  security_group_id            = aws_security_group.this["alb"].id
  description                  = "HTTPS from the NLB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.this["nlb"].id
}

# By address, not group: across the transit gateway a rule cannot name a group
# in the other VPC.
resource "aws_vpc_security_group_egress_rule" "alb_to_pods" {
  security_group_id = aws_security_group.this["alb"].id
  description       = "HTTP to app pods in the application VPC, across the transit gateway"
  ip_protocol       = "tcp"
  from_port         = local.app_port
  to_port           = local.app_port
  cidr_ipv4         = local.vpc_cidrs.application
}

# --- Nodes: the cluster ------------------------------------------------------

# The ALB's interfaces live in the perimeter's public subnets; across the
# transit gateway that address range is all the nodes can see of it.
resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  for_each = aws_subnet.perimeter_public

  security_group_id = aws_security_group.this["nodes"].id
  description       = "HTTP from the ALB's subnet in ${each.key}, across the transit gateway"
  ip_protocol       = "tcp"
  from_port         = local.app_port
  to_port           = local.app_port
  cidr_ipv4         = each.value.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_nodes" {
  security_group_id            = aws_security_group.this["nodes"].id
  description                  = "Node to node and pod to pod"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.this["nodes"].id
}

resource "aws_vpc_security_group_egress_rule" "nodes_to_nodes" {
  security_group_id            = aws_security_group.this["nodes"].id
  description                  = "Node to node and pod to pod"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.this["nodes"].id
}

resource "aws_vpc_security_group_egress_rule" "nodes_to_rds" {
  security_group_id            = aws_security_group.this["nodes"].id
  description                  = "PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.this["rds"].id
}

# The VPC's resolver sits at the base of its range plus two.
resource "aws_vpc_security_group_egress_rule" "nodes_dns" {
  for_each = toset(["udp", "tcp"])

  security_group_id = aws_security_group.this["nodes"].id
  description       = "DNS to the VPC resolver over ${each.key}"
  ip_protocol       = each.key
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_cidrs.application
}

# The one rule open to the internet, and the one exception to the security
# scan. Nodes pull the app image from GHCR (decided 2026-08-05) and reach AWS
# APIs — S3 for media, SSM, STS for IRSA — all on 443, out through the
# perimeter's NAT. GHCR publishes no stable address range to narrow this to.
# HTTPS only; nothing else leaves.
#trivy:ignore:aws-ec2-no-public-egress-sgr
resource "aws_vpc_security_group_egress_rule" "nodes_https_out" {
  security_group_id = aws_security_group.this["nodes"].id
  description       = "HTTPS out through NAT: image pulls from GHCR and AWS APIs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# --- RDS: the database ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = aws_security_group.this["rds"].id
  description                  = "PostgreSQL from cluster nodes"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.this["nodes"].id
}
