# The perimeter's way to the internet, and the only one in the design: the
# application VPC has no internet gateway at all and reaches the world across
# the transit gateway. Inert here — floci records the gateway and routes nothing.

resource "aws_internet_gateway" "perimeter" {
  vpc_id = aws_vpc.this["perimeter"].id

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-perimeter"
    Tier = "perimeter"
  })
}
