# Pointing this at real AWS instead of floci is the whole of the relationship
# with AWS — an endpoint change, not a rewrite.
#
# 127.0.0.1 rather than localhost, deliberately. floci binds 0.0.0.0, which is
# IPv4 only; `localhost` can resolve to ::1 first, and then the provider spends
# nine retries dialling an address nothing listens on before failing the apply.
variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://127.0.0.1:4566"
}
