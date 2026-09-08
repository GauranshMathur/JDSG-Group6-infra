locals {
  # Every name in every layer starts here.
  name_prefix = "twitter-clone"

  # Two zones, because the reference design puts a node group and a NAT gateway
  # in each. floci has no region isolation, so these are labels, not locations.
  availability_zones = ["us-east-1a", "us-east-1b"]

  # Three VPCs joined by a transit gateway — docs/architecture.md.
  vpc_cidrs = {
    perimeter   = "10.0.0.0/16"
    application = "10.1.0.0/16"
    dr          = "10.2.0.0/16"
  }

  # Everything in this layer applies and then does nothing: floci emulates the
  # control plane, routes no packet and enforces no rule. This tag says so in
  # state and in every plan, so a security group here is never mistaken for one
  # that filters traffic.
  inert = { Emulation = "inert" }
}
