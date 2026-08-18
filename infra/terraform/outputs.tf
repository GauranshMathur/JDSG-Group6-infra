output "media_bucket" {
  description = "The bucket Active Storage points at when the app moves off pod-local disk."
  value       = aws_s3_bucket.media.bucket
}

output "s3_kms_alias" {
  description = "The customer-managed key encrypting S3 objects."
  value       = aws_kms_alias.s3.name
}
