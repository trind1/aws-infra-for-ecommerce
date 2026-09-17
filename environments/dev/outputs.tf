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
# APPLICATION LOAD BALANCER
# ============================================================
output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = module.alb.alb_arn
}

output "alb_dns_name" {
  description = "AWS-assigned DNS name used by the HTTP CloudFront origin in the dev environment."
  value       = module.alb.alb_dns_name
}

output "alb_https_listener_arn" {
  description = "ARN of the optional ALB HTTPS test listener, or null when disabled."
  value       = module.alb.https_listener_arn
}

output "alb_imported_certificate_arn" {
  description = "ARN of the optional imported ACM certificate used by the ALB HTTPS test listener."
  value       = var.enable_alb_https_test ? module.alb_imported_certificate[0].certificate_arn : null
}

output "api_target_group_arn" {
  description = "ARN of the API target group used by the compute Auto Scaling Group."
  value       = module.alb.target_group_arn
}

# ============================================================
# FRONTEND
# ============================================================
output "frontend_bucket_id" {
  description = "ID of the private S3 bucket that stores frontend assets."
  value       = module.frontend.bucket_id
}

output "frontend_bucket_arn" {
  description = "ARN of the private S3 bucket that stores frontend assets."
  value       = module.frontend.bucket_arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution serving the frontend."
  value       = module.frontend.cloudfront_distribution_id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution serving the frontend."
  value       = module.frontend.cloudfront_distribution_arn
}

output "cloudfront_domain_name" {
  description = "Default CloudFront domain name for the frontend distribution."
  value       = module.frontend.cloudfront_domain_name
}

output "frontend_origin_access_control_id" {
  description = "ID of the Origin Access Control used by CloudFront for the private frontend bucket."
  value       = module.frontend.origin_access_control_id
}

# ============================================================
# COMPUTE
# ============================================================
output "autoscaling_group_name" {
  description = "Name of the API Auto Scaling Group."
  value       = module.compute.autoscaling_group_name
}

output "autoscaling_group_arn" {
  description = "ARN of the API Auto Scaling Group."
  value       = module.compute.autoscaling_group_arn
}

output "launch_template_id" {
  description = "ID of the EC2 launch template used by the API Auto Scaling Group."
  value       = module.compute.launch_template_id
}

output "compute_instance_role_arn" {
  description = "ARN of the IAM role assigned to API instances."
  value       = module.compute.instance_role_arn
}

output "compute_instance_profile_name" {
  description = "Name of the instance profile assigned to API instances."
  value       = module.compute.instance_profile_name
}

# ============================================================
# DATABASE
# ============================================================
output "rds_arn" {
  description = "ARN of the RDS database instance."
  value       = module.database.db_instance_arn
}

output "rds_identifier" {
  description = "Identifier of the RDS database instance."
  value       = module.database.db_instance_identifier
}

output "rds_endpoint" {
  description = "Endpoint of the RDS database instance for application configuration."
  value       = module.database.db_endpoint
}

output "rds_port" {
  description = "Port of the RDS database instance."
  value       = module.database.db_port
}

output "rds_address" {
  description = "DNS address of the RDS database instance without the port."
  value       = module.database.db_address
}

output "rds_subnet_group_name" {
  description = "Name of the RDS DB subnet group."
  value       = module.database.db_subnet_group_name
}

output "rds_log_group_names" {
  description = "RDS engine log group names keyed by exported log type."
  value       = module.database.rds_log_group_names
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
