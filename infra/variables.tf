variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "Project name — used as a prefix on all resource names"
  type        = string
  default     = "eks-gitops"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "github_org" {
  description = "GitHub org or username that owns the repo"
  type        = string
  default     = "fuhchu"
}

variable "github_repo" {
  description = "GitHub repo whose CI assumes the OIDC role to push images (the APP repo, not this config repo)"
  type        = string
  default     = "eks-gitops-app"
}
