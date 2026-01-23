module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 3.2.0"

  for_each = var.ecr_repos

  repository_name = "${var.environment}/${each.value}"

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        action = {
          type = "expire"
        }
        description  = "lifecycle"
        rulePriority = 1
        selection = {
          countNumber = 5
          countType   = "imageCountMoreThan"
          tagStatus   = "untagged"
        }
      }
    ]
  })

  repository_force_delete = true

  tags = var.tags
}