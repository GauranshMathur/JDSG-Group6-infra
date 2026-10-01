# What this layer needs from 10-network, found by name and tag against the
# emulator rather than read from that layer's state — the same convention as
# 40-data's key lookup (docs/decisions.md, 2026-09-30). It works because the
# workflow applies 10 before 20 in the same job. Rename a tag there and this
# breaks at plan time.

data "aws_vpc" "perimeter" {
  tags = {
    Name = "${local.name_prefix}-perimeter"
  }
}

data "aws_subnets" "perimeter_public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.perimeter.id]
  }

  tags = {
    Tier   = "perimeter"
    Access = "public"
  }
}

data "aws_security_group" "edge" {
  for_each = toset(["nlb", "alb"])

  name   = "${local.name_prefix}-${each.key}"
  vpc_id = data.aws_vpc.perimeter.id
}
