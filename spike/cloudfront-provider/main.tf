# Does an older AWS provider survive floci's CloudFront response?
#
# The I-1a spike found that floci accepts CreateDistribution and returns an
# object incomplete enough to segfault provider v6.59.0 reading it back
# (nil pointer in cloudfront.resourceDistributionFlatten). If an earlier
# provider tolerates the same response, the CloudFront question in
# docs/open-questions.md disappears and I-1b keeps its front door.
#
# Throwaway, like the spike before it. Deleted once the answer is recorded.
#
# Deliberately one resource with no dependencies: the original spike hung the
# distribution off an ALB, which cost a minute of waiting and gave the run a
# second way to fail. The origin is a static domain, because nothing here
# routes traffic anyway.
#
# `required_providers` is NOT here — Terraform forbids a variable in a version
# constraint, so the workflow writes versions.tf per matrix entry. That file
# is the only thing that differs between runs.

variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://localhost:4566"
}

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    cloudfront = var.endpoint
    sts        = var.endpoint
  }
}

# Identical in shape to the distribution that crashed v6.59.0, so a pass here
# means the provider version is the difference and not the configuration.
resource "aws_cloudfront_distribution" "probe" {
  enabled = true

  origin {
    origin_id   = "probe-origin"
    domain_name = "origin.example.com"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "probe-origin"
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Spike     = "cloudfront-provider"
    Throwaway = "true"
  }
}

output "distribution_id" {
  description = "Set only if the provider survived the read-back."
  value       = aws_cloudfront_distribution.probe.id
}
