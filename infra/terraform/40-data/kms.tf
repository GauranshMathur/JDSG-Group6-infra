# The key belongs to the foundation layer; this layer only uses it. It is found
# by alias, against the emulator, rather than read out of foundation's state:
# the alias is a stable public name, and a lookup needs no remote state sharing
# configured in HCP Terraform. It works because the workflow applies 00 before
# 40 in the same job, so the alias exists in this emulator by the time this runs.
#
# The cost is a weaker contract. Foundation's outputs.tf declares what it
# exposes; a lookup by name depends on a string, and renaming the alias there
# breaks this at plan time rather than at review.

data "aws_kms_alias" "s3" {
  name = "alias/${local.name_prefix}-s3"
}
