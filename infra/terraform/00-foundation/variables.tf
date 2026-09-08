# Pointing this at real AWS instead of floci is the whole of the relationship
# with AWS — an endpoint change, not a rewrite.
variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://localhost:4566"
}
