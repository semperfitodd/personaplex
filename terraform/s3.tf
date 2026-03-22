locals {
  s3_buckets = {
    ptfiles  = "ptfiles"
    wavfiles = "wavfiles"
  }
}

module "s3_bucket" {
  for_each = local.s3_buckets

  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.11.0"

  bucket = "${local.environment}-${each.value}-${random_string.this.result}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  force_destroy = false

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = var.tags
}
