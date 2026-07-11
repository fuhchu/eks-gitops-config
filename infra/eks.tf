# ── EKS Cluster ────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = var.project
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Nodes live in private subnets. The control plane ENIs are placed here too,
    # so it can communicate with kubelets on the nodes.
    subnet_ids = aws_subnet.private[*].id

    # endpoint_public_access = true  → kubectl from your laptop works
    # endpoint_private_access = true → nodes inside the VPC can reach the API server
    # Disabling public access is more secure but requires a bastion or VPN.
    # For a portfolio project, public + private is the right tradeoff.
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # API_AND_CONFIG_MAP: supports both the new Access Entry API (used for
  # github_actions in rbac.tf) and the legacy aws-auth ConfigMap (used
  # implicitly for the node role that EKS wires up automatically).
  # API-only would be cleaner but risks breaking the existing node group
  # mapping that was created under the old CONFIG_MAP-only mode.
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Must match the value AWS set implicitly when the cluster was first
    # created (true). Terraform treats this as immutable — leaving it
    # unset defaults to null, which is a DIFFERENT value than the
    # cluster's actual current state, forcing a destroy+recreate.
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = { Name = var.project }
}

# ── OIDC Provider for IRSA ─────────────────────────────────────────────────────
# EKS exposes its own OIDC endpoint. This lets Kubernetes ServiceAccounts
# assume IAM roles — pods get AWS credentials without any static keys.
# We need the TLS thumbprint of EKS's OIDC cert so AWS trusts it.

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ── Managed Node Group ─────────────────────────────────────────────────────────
# "Managed" means AWS handles node provisioning, OS patching, and draining
# on version upgrades. The alternative (self-managed) gives more control
# but you own the AMI and lifecycle — not worth it unless you need custom kernels.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # Nodes run in private subnets — they have no public IPs.
  # They pull images from ECR via NAT gateway, and reach the K8s API
  # via the private endpoint we enabled above.
  subnet_ids = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # RECOMMENDED: pin the AMI release version so a node group update doesn't
  # silently roll your nodes to a new OS version mid-session.
  # Leave null to always use the latest (fine for portfolio work).
  release_version = null

  update_config {
    # During a node group update, allow 1 node to be unavailable at a time.
    # With 2 nodes, this means rolling updates: drain node 1, replace, then node 2.
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_read,
  ]

  tags = { Name = "${var.project}-nodes" }
}

# ── EKS Addons ─────────────────────────────────────────────────────────────────
# aws-ebs-csi-driver: required in EKS 1.23+ to provision EBS-backed PVCs.
# Without this, any PVC using the gp2/gp3 StorageClass stays Pending forever.
# The node role already has the EC2 permissions the CSI driver needs.

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}
