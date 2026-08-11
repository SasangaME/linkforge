output "state_bucket_name" {
  description = "s3 bucket holding tfstate for remote backend"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "State bucket ARN — consumed by the OIDC role policies"
  value       = aws_s3_bucket.tfstate.arn
}