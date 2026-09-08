# What the layers above are allowed to depend on. Reading these needs remote
# state sharing enabled on this workspace.

output "s3_kms_key_arn" {
  description = "The customer-managed key that encrypts S3 objects."
  value       = aws_kms_key.s3.arn
}

output "s3_kms_alias" {
  description = "The alias of that key."
  value       = aws_kms_alias.s3.name
}
