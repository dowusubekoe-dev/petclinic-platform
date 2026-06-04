locals {
  # Required tags applied to every AWS resource via the provider default_tags.
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Resource name prefix: petclinic-prod-*
  name_prefix = "${var.project}-${var.environment}"
}

# Module calls (vpc, eks, ecr, rds, dns, secrets, observability) are added in
# their respective epics. This root module currently only wires up provider,
# backend, and shared locals.
