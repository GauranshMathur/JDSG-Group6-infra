# A NAT gateway per zone, in the perimeter's public subnets. They carry
# cluster-started egress only: the application VPC has no internet gateway, so
# its outbound traffic crosses the transit gateway to these and leaves through
# the perimeter. One per zone, so losing a zone does not take egress with it.
#
# The perimeter's transit subnets route to them — see route-tables.tf. Inert
# like the rest of this layer: floci allocates the addresses and records the
# gateways, and translates nothing.

resource "aws_eip" "nat" {
  for_each = local.az_index

  domain = "vpc"

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-nat-${each.key}"
    Tier = "perimeter"
  })
}

resource "aws_nat_gateway" "perimeter" {
  for_each = aws_subnet.perimeter_public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-nat-${each.key}"
    Tier = "perimeter"
  })

  # AWS requires the VPC's internet gateway before a public NAT gateway can
  # reach anything; nothing in the arguments above says so to Terraform.
  depends_on = [aws_internet_gateway.perimeter]
}
