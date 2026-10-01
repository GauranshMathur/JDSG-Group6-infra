locals {
  # Every name in every layer starts here.
  name_prefix = "twitter-clone"

  # floci records these and does nothing: no zone answers a query, no
  # certificate terminates a connection. The tag says so in state and in every
  # plan. See 10-network's locals.tf.
  inert = { Emulation = "inert" }
}
