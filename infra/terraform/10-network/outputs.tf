# What the layers above are allowed to depend on. Reading these from another
# layer needs remote state sharing enabled on this workspace in HCP Terraform.

output "vpc_ids" {
  description = "VPC id by tier — perimeter, application, dr."
  value       = { for tier, vpc in aws_vpc.this : tier => vpc.id }
}

output "vpc_cidrs" {
  description = "CIDR block by tier, so a layer above does not restate them."
  value       = local.vpc_cidrs
}
