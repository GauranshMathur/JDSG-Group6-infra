# One subnet per availability zone in each VPC that has something to put there.
# The DR VPC gets none yet: it stands ready, and nothing lands in it until the
# reliability layer does. Transit gateway attachment subnets come with the
# transit gateway.

locals {
  # az => index, so each subnet's CIDR is derived from its zone's position
  # rather than written out, and adding a third zone is one list entry.
  az_index = { for i, az in local.availability_zones : az => i }
}

# /24s. The perimeter's public subnets hold load balancers, NAT gateways and
# firewall endpoints — a handful of interfaces each — so 251 usable addresses is
# ample, and the rest of 10.0.0.0/16 stays free for what the edge adds later.
#
# "Public" is the role, not yet the fact: nothing routes to an internet gateway
# until the gateway and its route table land. And map_public_ip_on_launch stays
# off. Nothing here launches instances that want one — NAT takes an Elastic IP
# and load balancers manage their own — and Trivy's gate rightly refuses a
# subnet that hands public addresses out by default.
resource "aws_subnet" "perimeter_public" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this["perimeter"].id
  availability_zone = each.key
  cidr_block        = cidrsubnet(local.vpc_cidrs.perimeter, 8, each.value)

  tags = merge(local.inert, {
    Name   = "${local.name_prefix}-perimeter-public-${each.key}"
    Tier   = "perimeter"
    Access = "public"
  })
}

# /20s. EKS node groups live here, and the VPC CNI gives every pod an address
# from the node's subnet, so a /24 would run out of addresses long before it ran
# out of nodes. 4091 usable per zone; RDS shares the tier until it needs one of
# its own.
resource "aws_subnet" "application_private" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this["application"].id
  availability_zone = each.key
  cidr_block        = cidrsubnet(local.vpc_cidrs.application, 4, each.value)

  tags = merge(local.inert, {
    Name   = "${local.name_prefix}-application-private-${each.key}"
    Tier   = "application"
    Access = "private"
  })
}
