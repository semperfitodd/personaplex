output "hf_token_secret_name" {
  description = "Name of the HF token secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.hf_token.name
}

output "personaplex_irsa_role_arn" {
  description = "ARN of the IAM role for personaplex service account"
  value       = module.personaplex_irsa_role.iam_role_arn
}

output "s3_bucket_names" {
  description = "Names of the S3 buckets created for personaplex"
  value       = { for k, b in module.s3_bucket : k => b.s3_bucket_id }
}

output "s3_csi_service_account" {
  description = "Namespace and service account name for the S3 CSI driver"
  value       = "${var.environment}:${var.environment}-s3-sa"
}
