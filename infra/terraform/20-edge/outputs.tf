# What the layers above are allowed to depend on.

output "zone_id" {
  description = "The public hosted zone for the app's domain."
  value       = aws_route53_zone.this.zone_id
}

output "certificate_arn" {
  description = "The validated certificate for the app's domain — what the ALB's listener uses."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "nlb_dns_name" {
  description = "The NLB's public name — CloudFront's origin in the design."
  value       = aws_lb.nlb.dns_name
}

output "app_target_group_arn" {
  description = "Where the cluster's TargetGroupBinding registers the app's pods."
  value       = aws_lb_target_group.app.arn
}
