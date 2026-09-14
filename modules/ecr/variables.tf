variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "tags" {
  description = "Additional tags for the repository."
  type        = map(string)
  default     = {}
}
