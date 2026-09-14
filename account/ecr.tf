# One repository for the account, shared by every environment. Images are built
# once and promoted by digest, so the bytes verified in dev are the bytes that
# reach stage and prod. Putting this in account/ gives the shared artifact one
# owner and prevents a second environment state from trying to create it again.
module "ecr" {
  source = "../modules/ecr"

  repository_name = "linkforge"

  # Override only the milestone inherited from account's provider. Environment
  # remains "shared", matching both this state file and the repository's scope.
  tags = { Milestone = "v2-fargate" }
}
