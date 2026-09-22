output "vpc_id" {
  description = "VPC ID — referenced by 20-data and 30-cluster via remote state"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT GW)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes, RDS, ElastiCache)"
  value       = module.vpc.private_subnet_ids
}

output "private_route_table_ids" {
  description = "Private route table IDs — 30-cluster adds the NAT routes here"
  value       = module.vpc.private_route_table_ids
}

output "sg_nodes_id" {
  description = "EKS node security group ID"
  value       = module.vpc.sg_nodes_id
}

output "sg_rds_id" {
  description = "RDS security group ID"
  value       = module.vpc.sg_rds_id
}

output "sg_elasticache_id" {
  description = "ElastiCache security group ID"
  value       = module.vpc.sg_elasticache_id
}

output "sg_alb_id" {
  description = "ALB security group ID"
  value       = module.vpc.sg_alb_id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID — referenced by 30-cluster for NAT EIP"
  value       = module.vpc.internet_gateway_id
}
