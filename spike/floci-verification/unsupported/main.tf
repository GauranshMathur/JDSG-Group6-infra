# Question 2: what does floci do when an apply reaches an operation it does
# not implement — fail in a way Terraform can report, or return something that
# looks like success?
#
# This root is EXPECTED TO FAIL. Its value is in *how* it fails, which is why
# it is separate from `inert/`: here, an abort takes nothing else down with it.
#
# The worst available outcome is the quiet one. A clean error is a bad apply
# that announces itself; a shaped dummy response is a configuration that
# reports success and describes infrastructure that was never created. Every
# later decision about trusting `terraform apply` as a CI gate rests on which
# of those floci does.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

variable "endpoint" {
  description = "The floci endpoint every AWS service is reached through."
  type        = string
  default     = "http://localhost:4566"
}

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    globalaccelerator = var.endpoint
    sts               = var.endpoint
  }
}

# Global Accelerator is the probe: a real edge service, absent from every tier
# in docs/floci.md, and expressible in Terraform in four lines.
#
# If this turns out to be implemented after all, the probe has not failed —
# the answer is simply "floci is deeper than documented here", and the next
# run swaps in another absent service. What must not happen is reading a
# success here as an answer to the question; the question is about
# *unimplemented* operations, so a supported one answers nothing.
resource "aws_globalaccelerator_accelerator" "probe" {
  name = "spike-unsupported-probe"

  tags = {
    Spike     = "floci-verification"
    Throwaway = "true"
  }
}
