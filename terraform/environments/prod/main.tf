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

# ---------------------------------------------------------------------------
# Networking (Epic E-2) — VPC, public subnets, IGW, baseline security groups.
# CIDR 10.1.0.0/16 (prod); non-overlapping with dev (10.0.0.0/16).
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = ["${var.aws_region}a", "${var.aws_region}b"]
  tags                = local.common_tags
}

# Remaining module calls (eks, ecr, rds, dns, secrets, observability) are added
# in their respective epics.
