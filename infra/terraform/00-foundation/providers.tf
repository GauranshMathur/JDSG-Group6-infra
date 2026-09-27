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

  endpoints {
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
