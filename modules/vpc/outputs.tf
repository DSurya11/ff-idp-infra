output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets (for ALB, NAT Gateway)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets (for EKS nodes, RDS, ElastiCache)"
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "IDs of private route tables (30-cluster adds NAT routes here)"
  value       = aws_route_table.private[*].id
}

output "sg_nodes_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.nodes.id
}

output "sg_rds_id" {
  description = "Security group ID for RDS (allows from nodes only)"
  value       = aws_security_group.rds.id
}

output "sg_elasticache_id" {
  description = "Security group ID for ElastiCache (allows from nodes only)"
  value       = aws_security_group.elasticache.id
}

output "sg_alb_id" {
  description = "Security group ID for ALB (allows HTTP/HTTPS from internet)"
  value       = aws_security_group.alb.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}
