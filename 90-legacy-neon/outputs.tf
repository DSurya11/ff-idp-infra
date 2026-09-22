output "neon_project_id" {
  description = "Neon project ID (used as DATABASE_URL baseline for A/B test)"
  value       = neon_project.this.id
}

output "neon_connection_uri" {
  description = "Neon connection URI (pooled endpoint, used in A/B latency test)"
  value       = neon_project.this.connection_uri
  sensitive   = true
}
