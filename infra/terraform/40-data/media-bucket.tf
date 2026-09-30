# Media storage — the bucket Active Storage moves to when the app leaves
# pod-local disk. Application state, which is why it lives here beside where the
# database will, rather than in the foundation layer under a name that only ever
# meant "built first". Encrypted with a customer-managed key because the
# reference design says KMS encrypts S3, and because the Trivy gate refuses an
# unencrypted bucket.

resource "aws_s3_bucket" "media" {
  bucket = "${local.name_prefix}-media"
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.aws_kms_alias.s3.target_key_arn
    }
  }
}

# Media is served through the app's signed URLs, never by opening the bucket.
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
