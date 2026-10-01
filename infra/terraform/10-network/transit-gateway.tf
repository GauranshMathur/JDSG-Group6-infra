# The transit gateway joining the perimeter and application VPCs. The design's
# centralized egress: the application VPC has no internet gateway, so anything
# it sends out crosses here to the perimeter, through a NAT gateway, and out the
# internet gateway. This file is the fabric; the VPC route tables that send
# traffic into it are their own change.
#
# The DR VPC is not attached. It joins over inter-region peering in the design,
# and floci has no regions to peer between, so that stays on paper.
#
# Inert: floci records the gateway, attachments and routes and forwards nothing.

resource "aws_ec2_transit_gateway" "this" {
  description = "Joins the perimeter and application VPCs; centralized egress"

  # Routing is explicit, in the two tables below. The default table would
  # associate and propagate every attachment into one flat table, where any
  # spoke reaches any other.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  dns_support = "enable"

  tags = merge(local.inert, {
    Name = local.name_prefix
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.transit_attached

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.this[each.key].id
  subnet_ids = [
    for key, subnet in aws_subnet.transit : subnet.id if local.transit_subnets[key].tier == each.key
  ]

  # Must agree with the gateway's settings above.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-${each.key}"
    Tier = each.key
  })
}

# Two tables, the textbook egress layout. Spokes send everything to the
# perimeter; the perimeter sends each spoke's range back to it. A spoke's table
# has no route to another spoke, so they cannot reach each other through here.
resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = toset(["spokes", "egress"])

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-${each.key}"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "application" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["application"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["spokes"].id
}

resource "aws_ec2_transit_gateway_route_table_association" "perimeter" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["perimeter"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["egress"].id
}

# Everything from a spoke goes to the perimeter.
resource "aws_ec2_transit_gateway_route" "spokes_default" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["perimeter"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["spokes"].id
}

# Return traffic for the application VPC goes back to it.
resource "aws_ec2_transit_gateway_route" "egress_application" {
  destination_cidr_block         = local.vpc_cidrs.application
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this["application"].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this["egress"].id
}
