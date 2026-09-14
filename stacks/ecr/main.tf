module "ecr" {
  source = "../../modules/ecr"

  repository_name = "linkforge-${var.environment}"
  force_delete    = var.force_delete
}
