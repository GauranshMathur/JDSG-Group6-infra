# Routes are separate aws_route resources rather than route blocks inside the
# table, so the transit gateway can add its routes to these tables later without
# rewriting them — Terraform does not allow the two styles on one table.

# One table for both public subnets: they route identically, out through the
# internet gateway. This is what makes "public" a fact rather than a name.
resource "aws_route_table" "perimeter_public" {
  vpc_id = aws_vpc.this["perimeter"].id

  tags = merge(local.inert, {
    Name   = "${local.name_prefix}-perimeter-public"
    Tier   = "perimeter"
    Access = "public"
  })
}

resource "aws_route" "perimeter_public_internet" {
  route_table_id         = aws_route_table.perimeter_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.perimeter.id
}

resource "aws_route_table_association" "perimeter_public" {
  for_each = aws_subnet.perimeter_public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.perimeter_public.id
}

# --- Centralized egress ----------------------------------------------------
#
# application private subnet --0.0.0.0/0--> transit gateway (spokes table)
#   --> perimeter attachment --0.0.0.0/0--> NAT in the same zone
#   --> public subnet --0.0.0.0/0--> internet gateway
# and back: public subnet --10.1.0.0/16--> transit gateway (egress table)
#   --> application attachment --local--> the private subnet.
#
# Routes into the transit gateway wait for the attachments: AWS refuses a route
# to a gateway not yet attached to the route table's VPC.

# The application VPC's only way out. It has no internet gateway.
resource "aws_route_table" "application_private" {
  vpc_id = aws_vpc.this["application"].id

  tags = merge(local.inert, {
    Name   = "${local.name_prefix}-application-private"
    Tier   = "application"
    Access = "private"
  })
}

resource "aws_route" "application_private_egress" {
  route_table_id         = aws_route_table.application_private.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "application_private" {
  for_each = aws_subnet.application_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.application_private.id
}

# Traffic arriving at the perimeter from the transit gateway goes to the NAT in
# its own zone, so a zone's egress never depends on another zone. One table per
# zone, because each points at a different NAT.
resource "aws_route_table" "perimeter_transit" {
  for_each = local.az_index

  vpc_id = aws_vpc.this["perimeter"].id

  tags = merge(local.inert, {
    Name   = "${local.name_prefix}-perimeter-transit-${each.key}"
    Tier   = "perimeter"
    Access = "transit"
  })
}

resource "aws_route" "perimeter_transit_nat" {
  for_each = local.az_index

  route_table_id         = aws_route_table.perimeter_transit[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.perimeter[each.key].id
}

resource "aws_route_table_association" "perimeter_transit" {
  for_each = local.az_index

  subnet_id      = aws_subnet.transit["perimeter-${each.key}"].id
  route_table_id = aws_route_table.perimeter_transit[each.key].id
}

# The way back: replies leaving the NAT for the application VPC go to the
# transit gateway rather than out the internet gateway.
resource "aws_route" "perimeter_public_to_application" {
  route_table_id         = aws_route_table.perimeter_public.id
  destination_cidr_block = local.vpc_cidrs.application
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
