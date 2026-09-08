# State, locking and run history live in HCP Terraform. Terraform is never run
# by hand here: the `Terraform` workflow is the only thing that applies this
# configuration, which is why one workspace is enough and why there is no local
# path to keep in step with it.
#
# Runs execute on a self-hosted agent rather than HashiCorp's own workers,
# because a worker in HashiCorp's cloud has no route to the floci the job starts
# on the runner, and putting a fake AWS on the public internet to give it one is
# not on the table. The workflow starts the agent beside the emulator, where it
# reaches it on the same localhost:4566 the provider already defaults to.
#
# The workspace must exist before the first init, and must be set to Agent
# execution against the pool that issued TFC_AGENT_TOKEN. Neither is expressible
# here — see the README.

terraform {
  cloud {
    # TF_CLOUD_ORGANIZATION overrides this. The name is case-sensitive.
    organization = "JDSG-Group6"

    workspaces {
      name = "twitter-clone"
    }
  }
}
