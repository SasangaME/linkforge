# The account baseline: three settings that apply to everything created after
# them and to nothing created before. All three were unset on this account, so
# each is a default being chosen rather than a default being confirmed.
#
# None of these can ever be managed from CI. The `no_escalation` guardrail on
# every OIDC role denies `iam:Update*`, which covers UpdateAccountPasswordPolicy,
# and an account-wide switch is exactly the kind of blast radius that guardrail
# exists to keep away from a pipeline. This file is a second reason `account/`
# is applied by hand.

# --- S3 public access, account wide -------------------------------------

# The account-level override. It sits above every bucket policy and every ACL
# in the account, including buckets a later milestone has not created yet, and
# it cannot be overridden from inside a bucket.
#
# `bootstrap/` already blocks public access on the state bucket, and that stays.
# The two are not redundant in the way they look: this one is the control, and
# the bucket-level one is the statement of intent that survives if this is ever
# relaxed for some other bucket's sake.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- EBS encryption by default ------------------------------------------

# This one is REGIONAL, which the resource name does not say. It covers
# us-east-1 and no other region. Nothing in this project runs elsewhere until
# `v10-resilient` stands up a pilot-light region, and that region will start
# with default encryption off unless this resource is declared again there
# against a second provider alias. Write it down in that milestone; a plan in
# this module will never show the gap.
#
# It applies to volumes created after it and does not touch existing ones.
# There are none today, which is the point of doing it in `v0-bootstrap`:
# `v1-network` and `v2-fargate` create the first, and they inherit it.
#
# The key is the AWS-managed `aws/ebs` key, not a customer-managed one. A CMK
# is a `v4-state` decision and carries a real monthly cost per key; taking that
# on here would buy key rotation control this project has no use for yet.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# --- console password policy --------------------------------------------

# Worth being honest about what this does today: nothing. The account holds one
# IAM user, `devops-admin`, it is break-glass only, and it has no login profile
# — it authenticates with access keys, which a password policy does not govern.
#
# It is here because it is free and because the moment it stops being decorative
# is the moment somebody creates a console user, which is exactly the moment
# nobody is thinking about password rules. A policy that is already in place
# cannot be forgotten under pressure.
#
# `hard_expiry` stays false deliberately. True locks a user out at expiry
# instead of prompting for a new password, and recovering from that needs the
# root account. On an account whose only user is the break-glass identity, that
# is a self-lockout with extra steps.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
}
