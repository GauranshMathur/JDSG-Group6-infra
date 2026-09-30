# Keys, and nothing else. What the application stores lives in the data layer,
# which resolves this key by its alias rather than owning one.

resource "aws_kms_key" "s3" {
  description         = "Encrypts S3 objects for twitter-clone"
  enable_key_rotation = true
}

resource "aws_kms_alias" "s3" {
  name          = "alias/twitter-clone-s3"
  target_key_id = aws_kms_key.s3.key_id
}
