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

output "perimeter_public_subnet_ids" {
  description = "Public subnet id by availability zone, in the perimeter VPC."
  value       = { for az, subnet in aws_subnet.perimeter_public : az => subnet.id }
}

output "application_private_subnet_ids" {
  description = "Private subnet id by availability zone, in the application VPC."
  value       = { for az, subnet in aws_subnet.application_private : az => subnet.id }
}
