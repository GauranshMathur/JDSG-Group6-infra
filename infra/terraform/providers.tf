# Not real AWS: fake credentials, every credential and metadata check skipped,
# and one local endpoint for everything. Endpoints are listed per service as
# slices land, so the list doubles as an inventory of what this root touches.

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # ecr is here for a resource this root does not declare. A closed pull request
  # (#35) applied an aws_ecr_repository into this workspace, and closing it left
  # the resource in state with no configuration to match — so every plan since
  # has refreshed it. With no endpoint for the service, that refresh went to
  # *real* AWS, which rejected the fake credentials above and failed the plan.
  # Pointed at floci instead, the refresh finds nothing, Terraform drops the
  # entry, and nothing recreates it because nothing declares it. The line stays
  # afterwards: ECR is in the reference design, and a missing endpoint is how a
  # request reaches Amazon.
  endpoints {
    ecr = var.endpoint
    kms = var.endpoint
    s3  = var.endpoint
    sts = var.endpoint
  }

  default_tags {
    tags = {
      Project   = "twitter-clone"
      ManagedBy = "terraform"
    }
  }
}
