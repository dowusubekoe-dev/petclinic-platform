# Input variables for the petclinic vpc module.
# See docs/technical-spec.md#vpc-network-design and #terraform-modules.

variable "project" {
  description = "Project name, used for resource naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16 for dev, 10.1.0.0/16 for prod)."
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per AZ. Must align 1:1 with availability_zones."
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones for the public subnets. Must align 1:1 with public_subnet_cidrs."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs delivered to a dedicated, encrypted S3 bucket. Secure-by-default ON; disable per-env only with a documented cost justification."
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC flow log objects in S3 before lifecycle expiry."
  type        = number
  default     = 14
}
