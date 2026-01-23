locals {
  node_group_name     = "${var.environment}_cpu"
  node_group_name_gpu = "${var.environment}_gpu"
}

data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  name = "AmazonSSMManagedInstanceCore"
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.5.6"

  role_name             = "${local.environment}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
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
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
      most_recent              = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
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
    (local.node_group_name_gpu) = {
      instance_types = var.eks_node_gpu_instance_type
      capacity_type  = var.gpu_node_capacity_type
      min_size       = var.gpu_node_min_size
      max_size       = var.gpu_node_max_size
      desired_size   = var.gpu_node_desired_size

      enable_monitoring = true

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_volume_size
            volume_type           = var.node_volume_type
            iops                  = var.node_volume_type == "gp3" ? var.node_volume_iops : null
            throughput            = var.node_volume_type == "gp3" ? var.node_volume_throughput : null
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      labels = {
        workload-type            = "gpu"
        "nvidia.com/gpu.present" = "true"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        set -ex
        yum install -y cuda
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | sudo tee /etc/yum.repos.d/nvidia-docker.repo
        sudo yum install -y nvidia-container-toolkit
      EOT

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore       = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }

      tags = var.tags
    }

    (local.node_group_name) = {
      instance_types = var.eks_node_instance_type
      capacity_type  = var.cpu_node_capacity_type
      min_size       = var.cpu_node_min_size
      max_size       = var.cpu_node_max_size
      desired_size   = var.cpu_node_desired_size

      enable_monitoring = true

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_volume_size
            volume_type           = var.node_volume_type
            iops                  = var.node_volume_type == "gp3" ? var.node_volume_iops : null
            throughput            = var.node_volume_type == "gp3" ? var.node_volume_throughput : null
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      labels = {
        workload-type = "cpu"
      }

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore       = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }

      tags = var.tags
    }
  }

  depends_on = [module.vpc]
}
