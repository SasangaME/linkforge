output "repository_url" {
  description = "ECR URL used to tag and push images."
  value       = aws_ecr_repository.this.repository_url
}