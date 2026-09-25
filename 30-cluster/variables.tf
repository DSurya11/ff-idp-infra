variable "environment" {
  description = "Environment name tag (used in default_tags across all resources)"
  type        = string
  default     = "shared"
}

variable "allowed_cidr" {
  description = <<-EOF
    CIDR block allowed to reach the EKS API server public endpoint.
    Defaults to the IP recorded when this layer was written (2026-09-23).

    YOUR IP CHANGES BETWEEN SESSIONS — override when needed:
      terraform -chdir=30-cluster apply -var 'allowed_cidr=NEW.IP.HERE/32' -auto-approve

    To find your current IP:
      curl -s https://checkip.amazonaws.com

    DO NOT set to 0.0.0.0/0 permanently — anyone can enumerate cluster resources.
    Temporarily ok during a session if IP is unstable; revert before shutdown.
  EOF
  type        = string
  default     = "103.186.68.19/32"
}
