# What the layers above are allowed to depend on.

output "zone_id" {
  description = "The public hosted zone for the app's domain."
  value       = aws_route53_zone.this.zone_id
}

output "certificate_arn" {
  description = "The validated certificate for the app's domain — what the ALB's listener uses."
  value       = aws_acm_certificate_validation.this.certificate_arn
}
