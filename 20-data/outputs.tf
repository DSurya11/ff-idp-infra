output "rds_endpoint" {
  description = "RDS endpoint (host:port) — use this in the DATABASE_URL stored in Secrets Manager"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "RDS hostname only (no port)"
  value       = aws_db_instance.postgres.address
}

output "valkey_endpoint" {
  description = "ElastiCache Valkey primary endpoint"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "db_creds_secret_arn" {
  description = "ARN of the ff-idp/db-creds Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_creds.arn
}

output "jwt_secret_arn" {
  description = "ARN of the ff-idp/jwt-secret Secrets Manager secret"
  value       = aws_secretsmanager_secret.jwt_secret.arn
}

output "grafana_admin_secret_arn" {
  description = "ARN of the ff-idp/grafana-admin Secrets Manager secret"
  value       = aws_secretsmanager_secret.grafana_admin.arn
}

output "backstage_github_app_secret_arn" {
  description = "ARN of the ff-idp/backstage-github-app Secrets Manager secret"
  value       = aws_secretsmanager_secret.backstage_github_app.arn
}
