data "aws_iam_policy_document" "personaplex_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      aws_secretsmanager_secret.hf_token.arn
    ]
  }
}

module "personaplex_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.5.6"

  role_name = "${local.environment}-personaplex-secrets"

  role_policy_arns = {
    policy = aws_iam_policy.personaplex_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = var.personaplex_service_accounts
    }
  }

  tags = var.tags
}

resource "aws_iam_policy" "personaplex_secrets" {
  name        = "${local.environment}-personaplex-secrets"
  description = "Policy for personaplex service to access AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.personaplex_secrets.json
  tags        = var.tags
}

resource "aws_secretsmanager_secret" "hf_token" {
  name                    = "${local.environment}/hf-token"
  description             = "${local.environment} HF token"
  recovery_window_in_days = "7"
}

resource "aws_secretsmanager_secret_version" "hf_token" {
  secret_id = aws_secretsmanager_secret.hf_token.id
  secret_string = jsonencode(
    {
      HF_TOKEN = ""
    }
  )
}
