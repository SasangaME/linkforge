# `modules/ecr`

One private ECR repository and its storage lifecycle policy. The module knows
nothing about environments; [`account/`](../../account/) calls it once for the
repository shared by dev, stage, and prod.

## Interface

| Argument | Type | Default | Purpose |
| --- | --- | --- | --- |
| `repository_name` | string | — | Name of the repository |
| `tags` | map | `{}` | Extra repository tags |

| Output | Purpose |
| --- | --- |
| `repository_url` | Image name used by Docker and ECS |
| `repository_arn` | Repository identity used in IAM policies |
| `registry_id` | Registry identity used for ECR authentication |

## Decisions

- Tags are immutable. Builds use a commit-SHA tag or deploy by digest; they do
  not overwrite `latest`.
- Images are scanned when pushed.
- Untagged images expire after one day.
- Tagged images are retained until the deployment tagging contract exists in
  step 7. A count-based rule cannot tell whether ECS still references a digest.
- The repository is not force-deleted. It holds the artifact promoted across
  environments and is intentionally excluded from nightly dev teardown.
