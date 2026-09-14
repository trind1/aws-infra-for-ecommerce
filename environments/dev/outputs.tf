# ============================================================
# NETWORK
# ============================================================
output "vpc_id" {
  description = "ID of the environment VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by the ALB and compute tier."
  value       = module.network.public_subnet_ids
}

output "database_subnet_ids" {
  description = "IDs of the private database subnets used by RDS."
  value       = module.network.database_subnet_ids
}

# ============================================================
# SECURITY GROUPS
# ============================================================
output "alb_security_group_id" {
  description = "ID of the security group attached to the ALB."
  value       = module.security_groups.alb_security_group_id
}

output "application_security_group_id" {
  description = "ID of the security group attached to API instances."
  value       = module.security_groups.application_security_group_id
}

output "database_security_group_id" {
  description = "ID of the security group attached to RDS."
  value       = module.security_groups.database_security_group_id
}

# ============================================================
# CERTIFICATES
# ============================================================
output "alb_certificate_arn" {
  description = "Issued regional ACM certificate ARN for the ALB origin, or null until validation is confirmed."
  value       = module.certificates.alb_certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "Issued us-east-1 ACM certificate ARN for a custom CloudFront viewer domain, or null when not ready."
  value       = module.certificates.cloudfront_certificate_arn
}

output "alb_certificate_validation_records" {
  description = "ACM DNS validation CNAMEs for the regional ALB certificate."
  value       = module.certificates.alb_certificate_validation_records
}

output "cloudfront_certificate_validation_records" {
  description = "ACM DNS validation CNAMEs for the us-east-1 CloudFront viewer certificate."
  value       = module.certificates.cloudfront_certificate_validation_records
}

# ============================================================
# APPLICATION LOAD BALANCER
# ============================================================
output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = module.alb.alb_arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = module.alb.alb_dns_name
}

output "api_target_group_arn" {
  description = "ARN of the API target group used by the compute Auto Scaling Group."
  value       = module.alb.api_target_group_arn
}

# ============================================================
# FRONTEND
# ============================================================
output "frontend_bucket_id" {
  description = "ID of the private S3 bucket that stores frontend assets."
  value       = module.frontend.frontend_bucket_id
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution serving the frontend."
  value       = module.frontend.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "Default CloudFront domain name for the frontend distribution."
  value       = module.frontend.cloudfront_domain_name
}

# ============================================================
# COMPUTE
# ============================================================
output "autoscaling_group_name" {
  description = "Name of the API Auto Scaling Group."
  value       = module.compute.autoscaling_group_name
}

output "launch_template_id" {
  description = "ID of the EC2 launch template used by the API Auto Scaling Group."
  value       = module.compute.launch_template_id
}

output "compute_instance_role_arn" {
  description = "ARN of the IAM role assigned to API instances."
  value       = module.compute.instance_role_arn
}

# ============================================================
# DATABASE
# ============================================================
output "rds_arn" {
  description = "ARN of the RDS database instance."
  value       = module.database.rds_arn
}

output "rds_identifier" {
  description = "Identifier of the RDS database instance."
  value       = module.database.rds_identifier
}

output "rds_endpoint" {
  description = "Endpoint of the RDS database instance for application configuration."
  value       = module.database.rds_endpoint
}

output "rds_port" {
  description = "Port of the RDS database instance."
  value       = module.database.rds_port
}

# ============================================================
# MONITORING
# ============================================================
output "api_log_group_name" {
  description = "CloudWatch log group name for API application logs."
  value       = module.monitoring.api_log_group_name
}

output "system_log_group_name" {
  description = "CloudWatch log group name for API instance system logs."
  value       = module.monitoring.system_log_group_name
}

output "monitoring_metric_namespace" {
  description = "CloudWatch namespace used for application custom metrics."
  value       = module.monitoring.metric_namespace
}

output "monitoring_alarm_arns" {
  description = "CloudWatch alarm ARNs keyed by monitored signal."
  value       = module.monitoring.alarm_arns
}

output "monitoring_alarm_names" {
  description = "CloudWatch alarm names keyed by monitored signal."
  value       = module.monitoring.alarm_names
}
