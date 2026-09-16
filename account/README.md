# `account/`

The account-wide Terraform. One directory, one state file, one apply.

An administrator applies this module by hand from a workstation. No pipeline
applies it. [RUNBOOK.md](../RUNBOOK.md), operation 6, gives the steps and the
three reasons.

| File | What it makes |
| --- | --- |
| [oidc.tf](oidc.tf) | The GitHub OIDC provider and the two trust policies |
| [roles.tf](roles.tf) | The CI plan role, and one CI apply role for each environment |
| [workload_roles.tf](workload_roles.tf) | The roles that EC2 and ECS use, and two service-linked roles |
| [baseline.tf](baseline.tf) | The account security settings |
| [budget.tf](budget.tf) | The budget, its SNS topic, and the email subscription |
| [ecr.tf](ecr.tf) | The shared container image repository |

## Why there are no `dev`, `stage`, and `prod` directories

[`live/`](../live/) has one directory for each environment. This module has
none. That is a decision, not an omission.

There are two different types of resource in here.

**The account holds only one of some resources.** The OIDC provider, the
password policy, the EBS encryption default, the S3 public access block, the
budget, the two service-linked roles, and the ECR repository are all like this.
AWS holds one of each for the account. It does not hold one for each
environment.

Give those resources three state files, and three state files write to the same
object. The last apply wins. The other two show a change in every plan, and no
one owns the difference. Three directories do not separate these resources,
because AWS does not separate them. Three directories only cause a conflict.

**The account holds three of some other resources.** The CI apply roles and the
ECS task and execution roles are like this. The module makes one of each for
every name in `var.environments`. The result is
`linkforge-ecs-task-execution-dev`, then `-stage`, then `-prod`.

So this module does divide its work by environment. It does that with a loop in
the code, and not with three directories on the disk. Here the environment is an
input to one state. In `live/` the environment is a boundary between three
states.

## Three more reasons

**This module comes first.** It makes the OIDC provider and the CI roles. The
units in `live/` need those roles before they can run at all. A module that
makes the identity cannot be a consumer of the identity.

**No pipeline can apply it.** The budget email address would go into a log on a
public repository. The password policy needs `iam:UpdateAccountPasswordPolicy`,
and every CI role denies `iam:Update*`. Three directories would only give three
manual applies of the same one-per-account resources.

**The path would tell a lie.** In `live/`, Terragrunt takes the state key and
the `Environment` tag from the directory path. These resources are shared, and
their tag is `Environment = "shared"`. There is no directory with that name.
Put this module at `live/dev/account`, and both the tag and the state key become
wrong.

## Where to put a new resource

Ask how many of the resource the account holds.

- One for the whole account, or one that all environments share: put it here.
- One for each environment, and safe to destroy at night: put it in
  `live/<environment>/<stack>/`.

The ECR repository shows the second half of the first rule. The build makes an
image one time. Each environment then uses that same digest. Three repositories
would hold three copies of the same bytes, and the image in prod would not be
the image that dev tested.

## The exception, and it stays an exception

By the rule above, the ECS task and execution roles belong in `live/`. They are
here for a different reason. Every CI role carries the `no_escalation` policy,
which denies `iam:Create*` on all resources with an explicit Deny. An explicit
Deny is final. No permission added later can defeat it. So no stack in `live/`
can make an IAM role.

This is a compromise. The project has two workload identities today. If a later
milestone needs many more, do not let this module grow into a large collection
of service roles. Put those roles behind an IAM path with a permissions
boundary, and let each stack make its own.
[workload_roles.tf](workload_roles.tf) holds the same note.

## What changes at `v9-govern`

The boundary that separates the environments is the AWS account. It is not the
name of the environment. Today there is one account, so today there is one
`account/`.

At `v9-govern`, stage and prod move into their own accounts. Then each account
has its own `account/` state and its own provider, and the loop over
`var.environments` holds one name in each of them.

That is the correct line to divide on. Divide by environment now, and the work
must be done a second time.
