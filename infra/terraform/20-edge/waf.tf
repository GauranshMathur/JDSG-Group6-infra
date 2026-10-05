# The WAF in front of the app, on the ALB — the first hop that sees HTTP. AWS's
# own managed rule groups, nothing hand-written, evaluated cheapest first:
#
#   10  Amazon IP reputation list   addresses AWS has seen attacking, dropped first
#   20  Known bad inputs            request patterns with no legitimate use (Log4Shell and kin)
#   30  Common rule set             the OWASP-shaped baseline
#
# Everything they do not block is allowed. Each group reports metrics and keeps
# sampled requests, so a false positive can be found rather than guessed at.
#
# Inert: floci records the web ACL and its association and inspects nothing.

locals {
  waf_managed_rule_groups = {
    "aws-ip-reputation"   = { priority = 10, name = "AWSManagedRulesAmazonIpReputationList" }
    "aws-known-bad-input" = { priority = 20, name = "AWSManagedRulesKnownBadInputsRuleSet" }
    "aws-common"          = { priority = 30, name = "AWSManagedRulesCommonRuleSet" }
  }
}

resource "aws_wafv2_web_acl" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "AWS managed rule groups in front of the app's ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = local.waf_managed_rule_groups

    content {
      name     = rule.key
      priority = rule.value.priority

      # Use the group's own block and count actions, unchanged.
      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.value.name
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-alb"
    sampled_requests_enabled   = true
  }

  tags = merge(local.inert, {
    Name = "${local.name_prefix}-alb"
  })
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}
