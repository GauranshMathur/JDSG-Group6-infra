variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through. Pointing this (and the backend) at real AWS instead is the whole of the relationship with AWS — an endpoint change, not a rewrite."
  type        = string
  default     = "http://localhost:4566"
}
