variable "budget_alert_email" {
  description = "Inbox that receives the budget alerts. Must be confirmed by hand after the apply — see RUNBOOK.md."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.budget_alert_email))
    error_message = "The budget_alert_email value must be a single email address."
  }
}

variable "monthly_budget_limit" {
  description = "Monthly ceiling for the whole account, in USD. Budgets takes the amount as a string, not a number."
  type        = string
  default     = "10"
}
