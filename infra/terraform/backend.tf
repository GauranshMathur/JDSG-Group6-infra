# State lives in the emulator's S3 (I-2.7) — never on disk, never committed.
# Not for durability: a fresh emulator's bucket dies with it. It is the real
# pattern, and the identical configuration works against a persistent local
# floci, where state genuinely accumulates and incremental applies mean
# something.
#
# The bucket cannot be created by this configuration — it must exist before
# `terraform init`, which is the pipeline's one ordering problem. The
# terraform.yml workflow bootstraps it with the AWS CLI before init, reading
# the name from this block (the first `bucket =` in this directory by file
# sort order — keep it that way).
#
# A backend block cannot use variables, so the endpoint is hardcoded. It is
# the same one variables.tf defaults to: floci on localhost, whether that is
# a CI service container or a local `docker run`.
#
# Terraform 1.10+ locks natively in S3 (`use_lockfile`), so there is no
# DynamoDB lock table.

terraform {
  backend "s3" {
    bucket       = "twitter-clone-terraform-state"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true

    # Everything below says "not real AWS": one local endpoint, fake static
    # credentials, every credential and metadata check skipped.
    endpoints = {
      s3 = "http://localhost:4566"
    }
    access_key                  = "test"
    secret_key                  = "test"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
