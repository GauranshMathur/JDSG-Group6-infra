# The public hosted zone for the app's domain. In the design it holds the alias
# to CloudFront, which floci cannot apply (docs/decisions.md), so for now it
# holds only what the certificate needs to be validated.

resource "aws_route53_zone" "this" {
  name    = var.domain
  comment = "twitter-clone public zone"

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-${var.domain}"
  })
}
