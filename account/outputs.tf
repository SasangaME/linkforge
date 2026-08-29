output "gha_plan_role_arn" {
  description = "Role assumed by the pull request workflow — consumed by step 7"
  value       = aws_iam_role.gha_plan.arn
}

output "gha_apply_role_arn" {
  description = "Role assumed by the main branch workflow — consumed by step 7"
  value       = aws_iam_role.gha_apply.arn
}
output "budget_alert_topic_arn" {
  description = "SNS topic behind the budget alerts — used to check the subscription is confirmed"
  value       = aws_sns_topic.budget_alerts.arn
}
