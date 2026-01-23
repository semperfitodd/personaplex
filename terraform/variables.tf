variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cpu_node_capacity_type" {
  description = "Capacity type for CPU nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.cpu_node_capacity_type)
    error_message = "CPU node capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "cpu_node_desired_size" {
  description = "Desired number of CPU worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.cpu_node_desired_size >= 1
    error_message = "CPU node desired size must be >= 1."
  }
}

variable "cpu_node_max_size" {
  description = "Maximum number of CPU worker nodes"
  type        = number
  default     = 5

  validation {
    condition     = var.cpu_node_max_size >= 1
    error_message = "CPU node maximum size must be >= 1."
  }
}

variable "cpu_node_min_size" {
  description = "Minimum number of CPU worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.cpu_node_min_size >= 0
    error_message = "CPU node minimum size must be >= 0."
  }
}

variable "create_database_subnet_group" {
  description = "Create database subnet group for RDS/Aurora"
  type        = bool
  default     = false
}

variable "domain" {
  description = "Domain name for the application (e.g., example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]\\.[a-z]{2,}$", var.domain))
    error_message = "Domain must be a valid domain name format."
  }
}

variable "ecr_repos" {
  description = "Map of ECR repositories to create"
  type        = map(string)
  default     = {}
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.eks_cluster_version))
    error_message = "EKS cluster version must be in format X.Y (e.g., 1.31)."
  }
}

variable "eks_node_gpu_instance_type" {
  description = "EC2 instance types for GPU worker nodes (e.g., g4dn.xlarge, p3.2xlarge)"
  type        = list(string)

  validation {
    condition     = length(var.eks_node_gpu_instance_type) > 0
    error_message = "At least one GPU instance type must be specified."
  }
}

variable "eks_node_instance_type" {
  description = "EC2 instance types for CPU worker nodes"
  type        = list(string)

  validation {
    condition     = length(var.eks_node_instance_type) > 0
    error_message = "At least one CPU instance type must be specified."
  }
}

variable "enable_flow_log" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 32
    error_message = "Environment name must be between 1 and 32 characters."
  }
}

variable "flow_log_retention_days" {
  description = "Number of days to retain VPC Flow Logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "Flow log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "gpu_node_capacity_type" {
  description = "Capacity type for GPU nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.gpu_node_capacity_type)
    error_message = "GPU node capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "gpu_node_desired_size" {
  description = "Desired number of GPU worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.gpu_node_desired_size >= 0
    error_message = "GPU node desired size must be >= 0."
  }
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.gpu_node_max_size >= 1
    error_message = "GPU node maximum size must be >= 1."
  }
}

variable "gpu_node_min_size" {
  description = "Minimum number of GPU worker nodes"
  type        = number
  default     = 0

  validation {
    condition     = var.gpu_node_min_size >= 0
    error_message = "GPU node minimum size must be >= 0."
  }
}

variable "node_volume_iops" {
  description = "IOPS for gp3 volumes (3000-16000)"
  type        = number
  default     = 3000

  validation {
    condition     = var.node_volume_iops >= 3000 && var.node_volume_iops <= 16000
    error_message = "Node volume IOPS must be between 3000 and 16000."
  }
}

variable "node_volume_size" {
  description = "Size of the EBS volume for worker nodes (in GB)"
  type        = number
  default     = 100

  validation {
    condition     = var.node_volume_size >= 20 && var.node_volume_size <= 16384
    error_message = "Node volume size must be between 20 and 16384 GB."
  }
}

variable "node_volume_throughput" {
  description = "Throughput for gp3 volumes in MB/s (125-1000)"
  type        = number
  default     = 125

  validation {
    condition     = var.node_volume_throughput >= 125 && var.node_volume_throughput <= 1000
    error_message = "Node volume throughput must be between 125 and 1000 MB/s."
  }
}

variable "node_volume_type" {
  description = "EBS volume type for worker nodes"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.node_volume_type)
    error_message = "Node volume type must be one of: gp2, gp3, io1, io2."
  }
}

variable "region" {
  description = "AWS region where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "Region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "vpc_redundancy" {
  description = "Enable high availability with one NAT gateway per AZ (true) or single NAT gateway (false)"
  type        = bool
  default     = false
}
