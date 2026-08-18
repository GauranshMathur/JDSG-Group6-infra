# One root, no modules (CLAUDE.md); files split by concern. The EKS cluster is
# the one open question (module vs hand-rolled, docs/open-questions.md) and
# nothing in this root depends on its answer until eks.tf exists.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned deliberately: in the reference design a provider upgrade is a
      # decision, not a drive-by. 6.59 is the version the I-1a spikes
      # exercised against floci. Its one measured incompatibility is
      # CloudFront, which is omitted from this root (ADR 0002) — every
      # version from 4.67 to 6.59 crashes on it, so no pin escapes that.
      version = "~> 6.59"
    }
  }
}
