variable "neon_api_key" {
  type        = string
  sensitive   = true
  description = "Neon API key — from Neon console > Account Settings > API Keys"
}

variable "neon_project_id" {
  type        = string
  description = "Existing Neon project ID (imported, not created)"
}
