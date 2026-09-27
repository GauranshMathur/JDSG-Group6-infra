# Media storage — the bucket Active Storage moves to when the app leaves
# pod-local disk. Encrypted with a customer-managed key because the reference
# design says KMS encrypts S3, and because the Trivy gate refuses an
# unencrypted bucket.

resource "aws_kms_key" "s3" {
  description         = "Encrypts S3 objects for twitter-clone"
  enable_key_rotation = true
}

resource "aws_kms_alias" "s3" {
  name          = "alias/twitter-clone-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_s3_bucket" "media" {
  bucket = "twitter-clone-media"
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
      kms_master_key_id = aws_kms_key.s3.arn
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
