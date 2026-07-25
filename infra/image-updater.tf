# ── Argo CD Image Updater ──────────────────────────────────────────────────────
# Image Updater runs IN the cluster, polls ECR for new tags, and commits the new
# tag into this config repo. That moves image promotion out of CI entirely:
# CI only builds and pushes (keyless, via OIDC), and never needs a GitHub
# credential or any cluster access.
#
# It needs two things, both defined here:
#   1. IRSA role  -> read ECR (list tags on our repos)
#   2. A place to keep the git write credential (Secrets Manager -> ESO -> pod)

# ── IRSA role: let the Image Updater pod read ECR ──────────────────────────────
# Trust is locked to exactly the argocd/argocd-image-updater ServiceAccount —
# no other pod in the cluster can assume this role.

resource "aws_iam_role" "image_updater" {
  name = "${var.project}-image-updater"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:argocd:argocd-image-updater"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# READ-ONLY on ECR. Image Updater only needs to discover which tags exist; it
# never pushes. GetAuthorizationToken cannot be resource-scoped (an AWS quirk),
# but the actual image reads are scoped to this project's repositories.
resource "aws_iam_role_policy" "image_updater" {
  name = "${var.project}-image-updater-policy"
  role = aws_iam_role.image_updater.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-*"
        ]
      }
    ]
  })
}

# ── Secrets Manager: the git write credential ──────────────────────────────────
# Only the CONTAINER is created here — deliberately no aws_secretsmanager_secret_version.
# The token value is written out-of-band (aws secretsmanager put-secret-value),
# so the credential never lands in Terraform state or in git. Contrast with the
# Postgres password, which Terraform generates and therefore DOES sit in state.
#
# ESO reads this and materializes it as the `git-creds` Secret in the argocd
# namespace, where Image Updater picks it up — the same Secrets Manager -> ESO
# -> Kubernetes Secret pattern already used for Postgres.

resource "aws_secretsmanager_secret" "git_creds" {
  name = "${var.project}/git-creds"

  # 0 = delete immediately, so a destroy/re-apply cycle can reuse the name.
  recovery_window_in_days = 0

  tags = { Name = "${var.project}-git-creds" }
}

output "image_updater_role_arn" {
  description = "IRSA role ARN for the argocd-image-updater ServiceAccount"
  value       = aws_iam_role.image_updater.arn
}

output "git_creds_secret_name" {
  description = "Secrets Manager secret holding the git write credential"
  value       = aws_secretsmanager_secret.git_creds.name
}
