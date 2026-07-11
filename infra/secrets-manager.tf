# ── Generated Postgres password ────────────────────────────────────────────────
# Terraform generates the password. No human ever types it, and it appears in
# exactly two places: (1) Terraform state (encrypted in S3), and (2) AWS
# Secrets Manager. It never touches git, values.yaml, or your shell history.
#
# CAVEAT worth stating in interviews: the generated value DOES land in
# Terraform state in plaintext. That's an inherent Terraform limitation — the
# mitigation is an encrypted, access-restricted state backend (our S3 bucket),
# not pretending the secret isn't there. Teams that need to avoid even that
# generate the secret out-of-band and only reference its ARN in Terraform.

resource "random_password" "postgres" {
  length = 24
  # Exclude characters that need escaping inside a postgres:// URL or a shell.
  special          = true
  override_special = "-_"
}

# ── Secrets Manager secret ─────────────────────────────────────────────────────
# We store not just the password but the fully-formed connection strings.
# Building them here (where the password is known) means External Secrets can
# map keys 1:1 into Kubernetes with NO templating — which sidesteps the
# ESO {{ }} vs Helm {{ }} collision entirely.

resource "aws_secretsmanager_secret" "postgres" {
  name = "${var.project}/postgres"

  # Default is a 7–30 day "recovery window": a deleted secret name is reserved
  # and CANNOT be recreated until the window expires. That breaks the
  # destroy/re-apply cycle this portfolio project relies on. 0 = delete
  # immediately so `terraform apply` after a `destroy` can reuse the name.
  recovery_window_in_days = 0

  tags = { Name = "${var.project}-postgres" }
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    username           = "postgres"
    password           = random_password.postgres.result
    users_database_url = "postgresql://postgres:${random_password.postgres.result}@postgres:5432/usersdb"
    items_database_url = "postgresql://postgres:${random_password.postgres.result}@postgres:5432/itemsdb"
  })
}

# ── IRSA role for External Secrets Operator ────────────────────────────────────
# ESO's controller pod assumes this role via its ServiceAccount
# (external-secrets/external-secrets). Scoped to read ONLY this one secret —
# not all of Secrets Manager. A compromised ESO could read the postgres
# password, nothing else.

resource "aws_iam_role" "external_secrets" {
  name = "${var.project}-external-secrets"

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
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "${var.project}-external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_secretsmanager_secret.postgres.arn
    }]
  })
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator ServiceAccount"
  value       = aws_iam_role.external_secrets.arn
}

output "postgres_secret_name" {
  description = "Secrets Manager secret name referenced by ExternalSecret manifests"
  value       = aws_secretsmanager_secret.postgres.name
}
