resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # A release tag is an identity, not a pointer. Every build must use a new
  # commit-SHA tag or deploy by digest; `latest` cannot be pushed over or used
  # to trigger a redeployment. Steps 4 and 7 supply that image reference to
  # ECS rather than relying on a moving tag.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Untagged images cannot be deployed by a stable reference and accumulate when
# manifests move during a build. Tagged images are retained until step 7 defines
# the promotion tags and can protect every digest still referenced by an
# environment; a blind image-count rule cannot know that a task definition uses
# an older digest.
#
# One thing for step 7 to confirm rather than assume. This rule selects on tag
# status and nothing else, and a `docker buildx` manifest list has untagged
# per-architecture children hanging off a tagged index. Either the build stays
# single-architecture, or the rule is shown to leave the children of a
# referenced index alone — before it runs against the registry prod pulls from.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after one day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
    ]
  })
}
