output "repository_url" {
  description = "ECR URL used to tag and push images."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN used when another policy needs to name this repository."
  value       = aws_ecr_repository.this.arn
}

output "registry_id" {
  description = "AWS registry ID used by ECR authentication and image tooling."
  value       = aws_ecr_repository.this.registry_id
}
