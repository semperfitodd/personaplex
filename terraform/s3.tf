locals {
  bucket_names = {
    ".pt files" = "ptfiles"
    "wav files" = "wavfiles"
  }
}

module "s3_bucket" {
  for_each = local.bucket_names

  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.10.0"

  bucket = "${local.environment}-${each.value}-${random_string.this.result}"

  attach_public_policy = true

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  force_destroy = true

  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = var.tags
}