output "aws_region" {
  description = "AWS region for this environment."
  value       = var.aws_region
}

output "environment" {
  description = "Environment identifier."
  value       = var.environment
}

output "name_prefix" {
  description = "Resource name prefix (petclinic-{env})."
  value       = local.name_prefix
}

output "common_tags" {
  description = "Tags applied to all resources in this environment."
  value       = local.common_tags
}
