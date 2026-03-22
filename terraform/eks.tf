data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  name = "AmazonSSMManagedInstanceCore"
}

locals {
  cpu_node_group_name = "${var.environment}_cpu"
  gpu_node_group_name = "${var.environment}_gpu"

  gpu_toleration = [
    {
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }
  ]

  node_metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  node_block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = var.node_volume_size
        volume_type           = var.node_volume_type
        iops                  = var.node_volume_iops
        throughput            = var.node_volume_throughput
        encrypted             = true
        delete_on_termination = true
      }
    }
  }
}

module "csi_irsa_role_ebs" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name                  = "${local.environment}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

module "csi_irsa_role_s3" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name                            = "${local.environment}-s3-csi"
  use_name_prefix                 = false
  attach_mountpoint_s3_csi_policy = true
  mountpoint_s3_csi_bucket_arns   = [for b in module.s3_bucket : b.s3_bucket_arn]
  mountpoint_s3_csi_path_arns     = [for b in module.s3_bucket : "${b.s3_bucket_arn}/*"]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
    }
  }
}

module "csi_irsa_role_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name            = "${local.environment}-personaplex-secrets"
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = var.personaplex_service_accounts
    }
  }

  tags = var.tags
}

resource "aws_iam_policy" "personaplex_secrets_read" {
  name = "${local.environment}-personaplex-secrets-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = aws_secretsmanager_secret.hf_token.arn
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "personaplex_secrets_read" {
  policy_arn = aws_iam_policy.personaplex_secrets_read.arn
  role       = module.csi_irsa_role_secrets.name
}

module "voice_generator_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4.0"

  name            = "${local.environment}-voice-generator-sa"
  use_name_prefix = false

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = var.voice_generator_service_accounts
    }
  }

  tags = var.tags
}

resource "aws_iam_policy" "voice_generator_s3_write" {
  name = "${local.environment}-voice-generator-s3-write"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${module.s3_bucket["ptfiles"].s3_bucket_arn}/*"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "voice_generator_s3_write" {
  policy_arn = aws_iam_policy.voice_generator_s3_write.arn
  role       = module.voice_generator_irsa.name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15.1"

  name               = local.environment
  kubernetes_version = var.eks_cluster_version

  endpoint_private_access      = var.cluster_endpoint_private_access
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enable_cluster_creator_admin_permissions = true

  addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.csi_irsa_role_ebs.arn
      most_recent              = true
    }

    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.csi_irsa_role_s3.arn
      most_recent              = true
      configuration_values = jsonencode({
        node = {
          tolerations = local.gpu_toleration
        }
      })
    }

    aws-secrets-store-csi-driver-provider = {
      most_recent = true
      configuration_values = jsonencode({
        tolerations = local.gpu_toleration
        "secrets-store-csi-driver" = {
          syncSecret = {
            enabled = true
          }
          tolerations = local.gpu_toleration
        }
      })
    }

    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    metrics-server = {
      most_recent = true
    }

    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }

  cluster_tags = var.tags

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    (local.cpu_node_group_name) = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.eks_node_instance_type
      capacity_type  = var.cpu_node_capacity_type

      min_size     = var.cpu_node_min_size
      max_size     = var.cpu_node_max_size
      desired_size = var.cpu_node_desired_size

      metadata_options      = local.node_metadata_options
      block_device_mappings = local.node_block_device_mappings

      use_latest_ami_release_version = true
      ebs_optimized                  = true
      enable_monitoring              = true

      labels = {
        gpu = "false"
      }

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
      }

      tags = var.tags
    }

    (local.gpu_node_group_name) = {
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = var.gpu_node_instance_type
      capacity_type  = var.gpu_node_capacity_type

      min_size     = var.gpu_node_min_size
      max_size     = var.gpu_node_max_size
      desired_size = var.gpu_node_desired_size

      metadata_options      = local.node_metadata_options
      block_device_mappings = local.node_block_device_mappings

      use_latest_ami_release_version = true
      ebs_optimized                  = true
      enable_monitoring              = true

      labels = {
        gpu = "true"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
      }

      tags = var.tags
    }
  }

  depends_on = [module.vpc]
}
