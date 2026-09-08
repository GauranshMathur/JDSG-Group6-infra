# State, locking and run history for this layer live in HCP Terraform. Every
# directory under infra/terraform/ is its own root with its own workspace,
# applied in directory order by the Terraform workflow — see ../README.md.
#
# Terraform is never run by hand: the workflow is the only thing that applies
# this, so `terraform init` needs the network and a token, and there is no
# offline path.
#
# The workspace must exist before the first init and must be set to Agent
# execution against the pool that issued TFC_AGENT_TOKEN. Neither is
# expressible here.

terraform {
  cloud {
    # TF_CLOUD_ORGANIZATION overrides this. The name is case-sensitive.
    organization = "JDSG-Group6"

    workspaces {
      name = "twitter-clone-00"
    }
  }
}
