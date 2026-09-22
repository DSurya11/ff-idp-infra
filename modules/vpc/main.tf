# =============================================================================
# modules/vpc/main.tf
#
# Reusable VPC module for the ff-idp project.
#
# Creates:
#   - VPC with DNS hostnames + resolution enabled
#   - Public subnets (one per AZ) — for ALB, NAT Gateway EIP
#   - Private subnets (one per AZ) — for EKS nodes, RDS, ElastiCache
#   - Internet Gateway + public route table
#   - Private route tables (one per AZ, no default route — NAT added by 30-cluster)
#   - Security groups: nodes, RDS, ElastiCache, ALB
#
# NOT in this module: NAT Gateway. NAT lives in 30-cluster so it is destroyed
# nightly with the cluster. Private subnets have no 0.0.0.0/0 route while
# the cluster is down.
# =============================================================================

# ─── VPC ─────────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# ─── Public subnets ──────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  # Public subnets auto-assign public IPs to instances launched in them.
  # Needed for NAT Gateway EIP association.
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${var.availability_zones[count.index]}"
    # EKS uses this tag to discover subnets for external (internet-facing) load balancers
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ─── Private subnets ─────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.name}-private-${var.availability_zones[count.index]}"
    # EKS uses this tag to discover subnets for internal load balancers
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# ─── Route tables ────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route tables — one per AZ so the NAT Gateway in 30-cluster can
# add AZ-local routes (each AZ's private subnet → its own NAT GW EIP).
# Currently have no 0.0.0.0/0 route — that's added by 30-cluster when NAT is up.
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ─── Security Groups ──────────────────────────────────────────────────────────

# EKS Nodes — allow all egress (pods need to reach ECR, Secrets Manager, etc.)
# and node-to-node communication within the VPC.
resource "aws_security_group" "nodes" {
  name        = "${var.name}-nodes"
  description = "EKS managed node group security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Node-to-node (all traffic within SG)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-nodes-sg"
  }
}

# RDS — allow PostgreSQL from EKS nodes only
resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS PostgreSQL — allow from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds-sg"
  }
}

# ElastiCache — allow Valkey/Redis from EKS nodes only
resource "aws_security_group" "elasticache" {
  name        = "${var.name}-elasticache"
  description = "ElastiCache Valkey — allow from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Valkey from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-elasticache-sg"
  }
}

# ALB — allow HTTP and HTTPS from anywhere
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB — allow HTTP/HTTPS from internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-alb-sg"
  }
}
