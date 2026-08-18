# Everything about this provider says "not real AWS": fake static
# credentials, every credential and metadata check skipped, and one endpoint
# for all services — floci answers the whole AWS API surface on one port.
# Endpoints are listed per service as slices land, so the list is also an
# inventory of what this root actually touches.

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
