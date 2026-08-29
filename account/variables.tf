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

# The list is deliberately not "the environments that exist". It is the list of
# environments this repository knows how to build, and every one of them gets an
# identity and a state prefix from the start. Only dev is applied; stage and
# prod are unreachable because their GitHub Environments do not exist, not
# because their IAM does not. An empty role costs nothing and being able to read
# all three side by side is the point.
variable "environments" {
  description = "Environments that get a CI apply role and a state prefix. Order is irrelevant; the value is used as a set."
  type        = list(string)
  default     = ["dev", "stage", "prod"]

  validation {
    condition     = length(var.environments) == length(toset(var.environments))
    error_message = "The environments list must not repeat a name."
  }

  validation {
    condition     = alltrue([for e in var.environments : can(regex("^[a-z][a-z0-9-]*$", e))])
    error_message = "Environment names go into IAM role names and S3 key prefixes: lowercase letters, digits and hyphens only."
  }
}
