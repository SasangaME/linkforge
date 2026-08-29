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

data "aws_iam_policy_document" "gha_plan_trust" {
  statement {
    sid     = "GitHubActionsPullRequest"
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
      values   = ["${local.github_subject}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "gha_apply_trust" {
  statement {
    sid     = "GitHubActionsMainBranch"
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
      values   = ["${local.github_subject}:ref:refs/heads/main"]
    }
  }
}