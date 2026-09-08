# Customer-managed keys. The reference design says KMS encrypts S3, and the
# Trivy gate refuses an unencrypted bucket, so this key is load-bearing rather
# than decorative. The RDS and EBS keys join it here when their layers land —
# keys are foundation because several layers above depend on them.

resource "aws_kms_key" "s3" {
  description         = "Encrypts S3 objects for twitter-clone"
  enable_key_rotation = true
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${local.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}
