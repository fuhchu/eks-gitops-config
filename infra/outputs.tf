output "cluster_name" {
  description = "EKS cluster name — use in: aws eks update-kubeconfig --name <value>"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "ecr_urls" {
  description = "ECR repository URLs — use as image.repository in Helm values"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC — paste into workflow secrets"
  value       = aws_iam_role.github_actions.arn
}

output "node_role_arn" {
  description = "IAM role ARN for EKS nodes"
  value       = aws_iam_role.eks_nodes.arn
}
