output "hf_token_secret_name" {
  description = "Name of the HF token secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.hf_token.name
}

output "personaplex_irsa_role_arn" {
  description = "ARN of the IRSA role for the personaplex service account"
  value       = module.csi_irsa_role_secrets.arn
}

output "voice_generator_irsa_role_arn" {
  description = "ARN of the IRSA role for the voice-generator service account"
  value       = module.voice_generator_irsa.arn
}

output "s3_bucket_names" {
  description = "Names of the S3 buckets created for personaplex"
  value       = { for k, b in module.s3_bucket : k => b.s3_bucket_id }
}
