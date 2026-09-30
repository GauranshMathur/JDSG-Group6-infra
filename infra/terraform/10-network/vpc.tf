# The three VPCs, and nothing inside them yet. Subnets, gateways, routing and
# the transit gateway are their own files and their own pull requests — this one
# establishes the CIDR allocation the rest hangs off.

resource "aws_vpc" "this" {
  for_each = local.vpc_cidrs

  cidr_block = each.value

  # Names resolve inside the VPC; EKS and RDS both expect it later.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-${each.key}"
    Tier = each.key
  })
}
