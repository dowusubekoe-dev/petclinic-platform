# Input variables for the petclinic dns module.

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string
}

variable "tags" {
  description = "Additional tags merged onto all resources in this module."
  type        = map(string)
  default     = {}
}
