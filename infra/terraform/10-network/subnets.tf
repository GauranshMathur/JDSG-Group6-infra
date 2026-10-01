# One subnet per availability zone in each VPC that has something to put there.
# The DR VPC gets none yet: it stands ready, and nothing lands in it until the
# reliability layer does.

locals {
  # az => index, so each subnet's CIDR is derived from its zone's position
  # rather than written out, and adding a third zone is one list entry.
  az_index = { for i, az in local.availability_zones : az => i }
}

# /24s. The perimeter's public subnets hold load balancers, NAT gateways and
# firewall endpoints — a handful of interfaces each — so 251 usable addresses is
# ample, and the rest of 10.0.0.0/16 stays free for what the edge adds later.
#
# "Public" because route-tables.tf sends their traffic out through the internet
# gateway. And map_public_ip_on_launch stays off. Nothing here launches instances that want one — NAT takes an Elastic IP
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

# /28s for the transit gateway's attachments, one per zone in each attached VPC,
# carved from the top of the range so they never collide with the subnets above
# as those grow. AWS recommends attachments get their own subnets; here the
# perimeter needs them regardless, because its attachment subnets route to NAT
# while its public subnets route to the internet gateway, and a route table is
# per subnet. 11 usable addresses each — an attachment takes one per zone.
locals {
  transit_attached = {
    perimeter   = local.vpc_cidrs.perimeter
    application = local.vpc_cidrs.application
  }

  transit_subnets = merge([
    for tier, cidr in local.transit_attached : {
      for az, i in local.az_index : "${tier}-${az}" => {
        tier = tier
        az   = az
        cidr = cidrsubnet(cidr, 12, 4096 - length(local.availability_zones) + i)
      }
    }
  ]...)
}

resource "aws_subnet" "transit" {
  for_each = local.transit_subnets

  vpc_id            = aws_vpc.this[each.value.tier].id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr

  tags = merge(local.inert, {
    Name   = "${local.name_prefix}-${each.value.tier}-transit-${each.value.az}"
    Tier   = each.value.tier
    Access = "transit"
  })
}
