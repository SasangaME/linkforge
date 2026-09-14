module "ecr" {
  source = "../../modules/ecr"

  repository_name = "linkforge-${var.environment}"
}