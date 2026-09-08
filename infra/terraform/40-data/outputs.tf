output "media_bucket" {
  description = "The bucket Active Storage points at when the app moves off pod-local disk."
  value       = aws_s3_bucket.media.bucket
}
