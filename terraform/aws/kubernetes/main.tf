provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "mineclifford-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name                 = "mineclifford-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "Project"                                      = "mineclifford"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 18.0"
  cluster_name    = local.cluster_name
  cluster_version = "1.27"
  subnet_ids      = module.vpc.private_subnets

  vpc_id = module.vpc.vpc_id

  eks_managed_node_groups = {
    mineclifford = {
      desired_size = 2
      min_size     = 1
      max_size     = 3

      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 80
    }
  }

  # Allow external access to Kubernetes API
  cluster_endpoint_public_access = true

  node_security_group_additional_rules = {
    ingress_minecraft_java = {
      description                   = "Minecraft Java"
      protocol                      = "tcp"
      from_port                     = 25565
      to_port                       = 25565
      type                          = "ingress"
      cidr_blocks                   = ["0.0.0.0/0"]
    }
    ingress_minecraft_bedrock = {
      description                   = "Minecraft Bedrock"
      protocol                      = "udp"
      from_port                     = 19132
      to_port                       = 19132
      type                          = "ingress"
      cidr_blocks                   = ["0.0.0.0/0"]
    }
  }

  tags = {
    Project     = "mineclifford"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Create IAM role for EBS CSI driver
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.3"

  role_name             = "ebs-csi-controller-${local.cluster_name}"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Project     = "mineclifford"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Deploy Kubernetes Add-ons: EBS CSI Driver
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_id
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.16.0-eksbuild.1"
  service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn

  tags = {
    Project     = "mineclifford"
    Environment = "production"
    ManagedBy   = "terraform"
  }

  depends_on = [module.eks]
}