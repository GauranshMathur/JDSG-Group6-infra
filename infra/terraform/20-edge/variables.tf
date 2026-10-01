# Pointing this at real AWS instead of floci is the whole of the relationship
# with AWS — an endpoint change, not a rewrite.
variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://localhost:4566"
}

# .test is reserved (RFC 2606) and never delegated, so this name can collide
# with nothing real. A real deployment sets a domain it owns: the certificate's
# DNS validation only completes where the zone is actually delegated.
variable "domain" {
  description = "The name the app is served under, and the hosted zone that holds it."
  type        = string
  default     = "twitter-clone.test"
}
