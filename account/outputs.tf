output "gha_plan_role_arn" {
  description = "Role assumed by the pull request workflow — consumed by step 7"
  value       = aws_iam_role.gha_plan.arn
}

# A map, and every environment appears in it whether or not anything is
# deployed there. An ARN in this output is not a claim that the role can be
# assumed — see RUNBOOK.md, operation 5, for what makes one reachable.
output "gha_apply_role_arns" {
  description = "Role assumed by a workflow job declaring the matching `environment:`, keyed by environment name"
  value       = { for env, role in aws_iam_role.gha_apply : env => role.arn }
}

output "budget_alert_topic_arn" {
  description = "SNS topic behind the budget alerts — used to check the subscription is confirmed"
  value       = aws_sns_topic.budget_alerts.arn
}

# The name is the contract between account/ and live/<env>/network. The stack
# looks the profile up with a data source rather than reading this state, so a
# missing account/ apply fails at plan with "no matching instance profile"
# rather than at boot with an instance that never registers.
output "ssm_host_instance_profile_name" {
  description = "Instance profile named by the EC2 host in live/<env>/network."
  value       = aws_iam_instance_profile.ssm_host.name
}

output "ecr_repository_url" {
  description = "Shared image repository used by every LinkForge environment."
  value       = module.ecr.repository_url
}

output "ecr_repository_arn" {
  description = "Shared repository ARN used when image pipeline permissions are added."
  value       = module.ecr.repository_arn
}

output "ecr_registry_id" {
  description = "Registry ID used to authenticate image build and release tooling."
  value       = module.ecr.registry_id
}
