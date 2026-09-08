# State, locking and run history live in HCP Terraform. Runs execute on a
# self-hosted agent rather than HashiCorp's own workers, because a worker in
# HashiCorp's cloud has no route to a floci on localhost and putting a fake AWS
# on the public internet is not on the table. The agent runs beside the
# emulator and reaches it exactly as a local `terraform apply` would.
#
# Two workspaces, selected by TF_WORKSPACE, because they mean different things:
#
#   twitter-clone-local   the persistent floci from infra/docker/floci-compose.yml,
#                         where state accumulates and an incremental apply means
#                         something
#   twitter-clone-ci      the throwaway emulator in terraform.yml, wiped with the
#                         runner. Its state describes nothing between runs, so
#                         every plan there reads as a first-time create — which
#                         is the check working, not the check broken
#
# Both must exist before the first init and both must be set to Agent execution
# against the same pool; neither is expressible here, so see the README. The
# free tier allows one agent at a time, so a local agent left running will
# starve a CI run.
#
# `terraform init` now needs the network and a token — `terraform login`, or
# TF_TOKEN_app_terraform_io. There is no offline path any more.

terraform {
  cloud {
    # TF_CLOUD_ORGANIZATION overrides this if the organization is named otherwise.
    organization = "jdsg-group6"

    workspaces {
      tags = ["twitter-clone"]
    }
  }
}
