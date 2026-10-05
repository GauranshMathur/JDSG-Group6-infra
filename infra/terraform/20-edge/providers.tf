# Not real AWS: fake credentials, every credential and metadata check skipped,
# and one local endpoint for everything. Endpoints are listed per service as
# resources land, so the list doubles as an inventory of what this root touches
# — and a service left out is not inert, it is a request to Amazon.

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    acm     = var.endpoint
    ec2     = var.endpoint
    elbv2   = var.endpoint
    route53 = var.endpoint
    sts     = var.endpoint
    wafv2   = var.endpoint
  }

  default_tags {
    tags = {
      Project   = "twitter-clone"
      ManagedBy = "terraform"
    }
  }
}
