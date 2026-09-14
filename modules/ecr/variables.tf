variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "force_delete" {
  description = "Whether Terraform may delete images before deleting the repository."
  type        = bool
  default     = false
}
