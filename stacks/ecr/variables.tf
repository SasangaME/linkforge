variable "environment" {
  description = "Environment name used in the repository name."
  type        = string
}

variable "force_delete" {
  description = "Whether this environment's ECR repository may be removed with its images."
  type        = bool
}
