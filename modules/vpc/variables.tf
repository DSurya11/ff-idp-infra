variable "name" {
  description = "Name prefix for all resources in this VPC"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used for subnet tags that EKS uses for load balancer discovery"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones. Must match the count of public and private subnet CIDRs."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ"
  type        = list(string)
}
