# petclinic vpc module
#
# All-public subnet design (no NAT Gateway, no private subnets, no VPC
# endpoints) to minimise cost for learning. Security groups are the primary
# access-control perimeter. See docs/adr/0001-public-subnets.md.

locals {
  name_prefix = "${var.project}-${var.environment}"

  # EKS requires public subnets tagged with the cluster association ("shared")
  # and the ELB role so the AWS Load Balancer Controller can auto-discover them.
  eks_subnet_tags = {
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  }
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Public subnets — host ALL resources (EKS nodes, RDS, ALB)
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  #checkov:skip=CKV_AWS_130:All-public subnet design is intentional (ADR-0001); SGs are the perimeter, no NAT/private subnets for cost
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, local.eks_subnet_tags, {
    Name = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
  })

  lifecycle {
    precondition {
      condition     = length(var.availability_zones) == length(var.public_subnet_cidrs)
      error_message = "availability_zones and public_subnet_cidrs must have the same length (one AZ per subnet)."
    }
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway + single public route table (0.0.0.0/0 -> IGW)
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Lock down the VPC's default security group (deny all ingress/egress).
# Nothing should ever use it — all access flows through the purpose-built SGs
# below. Defining the resource with no rules revokes AWS's default allow-rules.
# ---------------------------------------------------------------------------
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-default-sg-locked"
  })
}

# ===========================================================================
# Security Groups — the primary access-control perimeter (all-public design).
# Cross-referencing SGs use standalone rule resources to avoid dependency
# cycles (cluster <-> node, node <-> alb, rds <- node).
# ===========================================================================

# --- EKS control plane SG ---
resource "aws_security_group" "eks_cluster" {
  #checkov:skip=CKV2_AWS_5:Module output SG; attached by the eks module control plane (PETPLAT-12)
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane: Kubernetes API access from worker nodes."
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

# --- EKS worker node SG ---
resource "aws_security_group" "eks_node" {
  #checkov:skip=CKV2_AWS_5:Module output SG; attached by the eks managed node group (PETPLAT-13)
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker nodes: intra-cluster, kubelet, and NodePort traffic."
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })
}

# --- RDS (MySQL) SG ---
resource "aws_security_group" "rds" {
  #checkov:skip=CKV2_AWS_5:Module output SG; attached by the rds module DB instance (PETPLAT-19+)
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL: 3306 from EKS worker nodes only."
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

# --- ALB (public-facing) SG ---
resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Module output SG; attached by the AWS Load Balancer Controller ingress (DNS epic)
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: public HTTP/HTTPS in, NodePort/health-check out to nodes."
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# ---- EKS cluster SG rules ----
resource "aws_vpc_security_group_ingress_rule" "cluster_api_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "Kubernetes API server (443) from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.eks_node.id
}

resource "aws_vpc_security_group_egress_rule" "cluster_all_out" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound from control plane"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---- EKS node SG rules ----
resource "aws_vpc_security_group_ingress_rule" "node_all_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from EKS control plane"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "node_all_from_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication (self)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_node.id
}

resource "aws_vpc_security_group_ingress_rule" "node_kubelet_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Kubelet API (10250) from control plane"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.eks_cluster.id
}

resource "aws_vpc_security_group_ingress_rule" "node_nodeport_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort services (30000-32767) from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "node_all_out" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound from worker nodes"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---- RDS SG rules ----
resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL (3306) from EKS worker nodes only"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.eks_node.id
}

# ---- ALB SG rules ----
# ALB is intentionally public-facing per the technical spec (Security Groups).
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:ALB is intentionally public-facing per technical-spec Security Groups
  security_group_id = aws_security_group.alb.id
  description       = "HTTP (80) from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS (443) from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes_nodeport" {
  security_group_id            = aws_security_group.alb.id
  description                  = "NodePort target group traffic (30000-32767) to nodes"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.eks_node.id
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodes_health" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Health checks (8080) to nodes"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.eks_node.id
}
