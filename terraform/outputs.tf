output "personaplex_irsa_role_arn" {
  description = "ARN of the IAM role for personaplex service account"
  value       = module.personaplex_irsa_role.iam_role_arn
}

output "hf_token_secret_name" {
  description = "Name of the HF token secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.hf_token.name
}
