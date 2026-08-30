# GitHub changed the OIDC subject claim format for repositories created after
# 15 July 2026. A repository from before that date is named in the subject as
# repo:SasangaME/linkforge. One created after it carries the numeric owner and
# repository IDs alongside the names. This repository was created on
# 2026-08-11, so it emits the second form and only the second form.
#
# The IDs are the point of the format. They never change, so renaming the
# repository or the account no longer moves this trust to whoever claims the
# old name — which the name-based form allowed.
#
# They are literals because nothing in AWS can derive them. Read them back with:
#   curl -s https://api.github.com/repos/SasangaME/linkforge | jq '.id, .owner.id'
locals {
  github_owner    = "SasangaME"
  github_owner_id = 12818777
  github_repo     = "linkforge"
  github_repo_id  = 1330896942

  # repo:SasangaME@12818777/linkforge@1330896942
  github_subject = "repo:${local.github_owner}@${local.github_owner_id}/${local.github_repo}@${local.github_repo_id}"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# Two subjects, not one, and the second was forced by v1-network. `apply.yml`
# plans on a push to main before the reviewer gate, on this role, because a job
# that assumed the apply role would have to declare `environment: dev` and would
# therefore run only after approval — a plan the reviewer cannot read in time.
# So the pre-gate plan runs here, and a push emits :ref:refs/heads/main.
#
# StringEquals over a list is an OR across exact matches, so this widens the
# role to any push-triggered workflow on main and to nothing else. That is
# affordable for exactly the reason the role's scope was fixed at ReadOnlyAccess
# in step 4: a role that cannot mutate has no blast radius to widen.
#
# release/* joins this list when stage and prod are promoted, and it will not
# fit — StringEquals does not wildcard, so that day the condition becomes
# StringLike over :ref:refs/heads/release/*.
data "aws_iam_policy_document" "gha_plan_trust" {
  statement {
    sid     = "GitHubActionsPlan"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.github_subject}:pull_request",
        "${local.github_subject}:ref:refs/heads/main",
      ]
    }
  }
}

# The apply role is per environment, and the claim it pins is not the branch.
# A job that declares `environment: dev` gets a subject ending in
# :environment:dev — the ref segment is replaced, not appended. Both cannot be
# pinned at once, so the branch requirement moves to the environment's
# deployment branch policy in GitHub, and the reviewer that guards prod moves
# there too. The trigger, the `environment:` key and this trust policy are now
# one decision written in three places.
#
# All three roles exist from the start; only dev is reachable. GitHub will not
# mint a token carrying a claim for an environment it holds no record of, so a
# role whose GitHub Environment has not been created cannot be assumed by
# anyone. That, rather than a commented-out resource, is what keeps stage and
# prod inert while only dev is applied. See RUNBOOK.md, operation 5.
data "aws_iam_policy_document" "gha_apply_trust" {
  for_each = toset(var.environments)

  statement {
    sid     = "GitHubActionsEnvironment"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_subject}:environment:${each.key}"]
    }
  }
}
