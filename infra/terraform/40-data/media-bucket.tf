# Media storage — the bucket Active Storage moves to when the app leaves
# pod-local disk. Application state, which is why it lives here beside the
# database rather than in the foundation layer, and why it reaches across for
# the key rather than owning one.

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
      kms_master_key_id = data.terraform_remote_state.foundation.outputs.s3_kms_key_arn
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
