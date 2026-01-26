locals {
  node_group_name     = "${var.environment}_cpu"
  node_group_name_gpu = "${var.environment}_gpu"

  node_metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }
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
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.eks_node_gpu_instance_type
      capacity_type  = var.gpu_node_capacity_type
      min_size       = var.gpu_node_min_size
      max_size       = var.gpu_node_max_size
      desired_size   = var.gpu_node_desired_size

      enable_monitoring = true

      metadata_options = local.node_metadata_options

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
        gpu = "true"
      }

      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        set -ex

        dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r) gcc make

        BASE_URL="https://us.download.nvidia.com/tesla"
        DRIVER_VERSION="550.127.05"
        DRIVER_FILE="NVIDIA-Linux-x86_64-$${DRIVER_VERSION}.run"

        curl -fSsl -O "$${BASE_URL}/$${DRIVER_VERSION}/$${DRIVER_FILE}"
        chmod +x "$${DRIVER_FILE}"
        ./"$${DRIVER_FILE}" --silent --install-libglvnd

        dnf config-manager --add-repo https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
        dnf install -y nvidia-container-toolkit
        nvidia-ctk runtime configure --runtime=containerd
        systemctl restart containerd
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

      metadata_options = local.node_metadata_options

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
