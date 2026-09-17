# The reference design names an ECR repository for the app image; applied for
# completeness so the diagram and the Terraform agree. The cluster actually
# pulls from ghcr.io/gauranshmathur/twitter-clone-web (docs/decisions.md,
# 2026-08-05) — nothing reads from or writes to this repository.

resource "aws_ecr_repository" "app" {
  name                 = "twitter-clone-web"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
