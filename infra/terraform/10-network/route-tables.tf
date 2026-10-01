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
