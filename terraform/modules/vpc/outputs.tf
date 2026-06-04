# Outputs for the petclinic vpc module.
# See docs/technical-spec.md#terraform-modules (Module: vpc).

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "eks_cluster_sg_id" {
  description = "EKS control plane security group ID."
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID."
  value       = aws_security_group.eks_node.id
}

output "rds_sg_id" {
  description = "RDS security group ID."
  value       = aws_security_group.rds.id
}

output "alb_sg_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "flow_logs_bucket" {
  description = "Name of the VPC flow logs S3 bucket (null when flow logs are disabled)."
  value       = one(aws_s3_bucket.flow_logs[*].bucket)
}
