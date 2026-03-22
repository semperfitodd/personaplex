resource "aws_secretsmanager_secret" "hf_token" {
  name                    = "${local.environment}/hf-token-${random_string.this.result}"
  description             = "HuggingFace API token for ${local.environment}"
  recovery_window_in_days = 7
}
