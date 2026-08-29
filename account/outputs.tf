output "gha_plan_role_arn" {
  description = "Role assumed by the pull request workflow — consumed by step 7"
  value       = aws_iam_role.gha_plan.arn
}

output "gha_apply_role_arn" {
  description = "Role assumed by the main branch workflow — consumed by step 7"
  value       = aws_iam_role.gha_apply.arn
}