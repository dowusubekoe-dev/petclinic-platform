provider "aws" {
  region = var.aws_region

  # Required tags are applied to every AWS resource that supports tagging.
  default_tags {
    tags = local.common_tags
  }
}
