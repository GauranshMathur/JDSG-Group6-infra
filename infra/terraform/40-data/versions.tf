terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned: 6.59 is what the floci spikes were run against.
      version = "~> 6.59"
    }
  }
}
