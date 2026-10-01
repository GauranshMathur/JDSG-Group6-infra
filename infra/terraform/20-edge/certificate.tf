# The certificate the ALB terminates TLS with, validated by DNS in the zone
# above. One name, the apex: there is one app on one host.

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain
  validation_method = "DNS"

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-${var.domain}"
  })

  # A replacement certificate must exist before the listener lets go of the old.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.this.domain_validation_options : option.domain_name => option
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

# Waits for the certificate to be issued. Bounded to five minutes rather than
# the provider's seventy-five, so a certificate that is never going to issue
# fails the job promptly instead of eating its whole timeout.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]

  timeouts {
    create = "5m"
  }
}
