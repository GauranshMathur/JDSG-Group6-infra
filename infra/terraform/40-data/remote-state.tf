# The key this layer encrypts with belongs to the foundation layer. This is the
# seam between roots: 00-foundation declares in its outputs.tf what it exposes,
# and this reads exactly that and nothing more.
#
# Needs remote state sharing enabled on twitter-clone-00, or the read is denied.

data "terraform_remote_state" "foundation" {
  backend = "remote"

  config = {
    organization = "JDSG-Group6"

    workspaces = {
      name = "twitter-clone-00"
    }
  }
}
