# Pointing this at real AWS instead of floci is the whole of the relationship
# with AWS — an endpoint change, not a rewrite.
variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://localhost:4566"
}

# AWS's own list by default, so on real AWS the NLB admits CloudFront exactly as
# AWS publishes it. floci has no AWS-managed lists and, like AWS, refuses the
# reserved com.amazonaws. prefix for any other, so the workflow seeds a stand-in
# under its own name and points this at it with a generated emulator.auto.tfvars.
variable "cloudfront_prefix_list_name" {
  description = "The managed prefix list holding CloudFront's origin-facing addresses."
  type        = string
  default     = "com.amazonaws.global.cloudfront.origin-facing"
}
