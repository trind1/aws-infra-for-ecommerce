locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ============================================================
# MODULE: NETWORK
# ============================================================
module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  environment  = var.environment

  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs

  # Common tags are applied by the provider default_tags configuration.
}

# ============================================================
# MODULE: SECURITY GROUPS
# ============================================================
module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  environment  = var.environment

  vpc_id                           = module.network.vpc_id
  cloudfront_origin_prefix_list_id = var.cloudfront_origin_prefix_list_id
  alb_listener_port                = var.alb_listener_port
  application_port                 = var.application_port
  database_port                    = var.database_port

  # Common tags are applied by the provider default_tags configuration.
}

# ============================================================
# MODULE: CERTIFICATES
# ============================================================
module "certificates" {
  source = "../../modules/certificates"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment

  alb_origin_domain             = var.alb_origin_domain
  alb_subject_alternative_names = var.alb_subject_alternative_names
  alb_route53_zone_id           = var.alb_route53_zone_id
  alb_certificate_ready         = var.alb_certificate_ready

  enable_custom_viewer_domain          = var.enable_custom_viewer_domain
  cloudfront_viewer_domain             = var.cloudfront_viewer_domain
  cloudfront_subject_alternative_names = var.cloudfront_subject_alternative_names
  cloudfront_route53_zone_id           = var.cloudfront_route53_zone_id
  cloudfront_certificate_ready         = var.cloudfront_certificate_ready
}

# ============================================================
# MODULE: APPLICATION LOAD BALANCER
# ============================================================
module "alb" {
  source = "../../modules/alb"

  project_name = var.project_name
  environment  = var.environment

  # Network, security-group and certificate inputs are added with this module.
}

# ============================================================
# MODULE: FRONTEND
# ============================================================
module "frontend" {
  source = "../../modules/frontend"

  project_name = var.project_name
  environment  = var.environment

  # ALB origin, CloudFront and S3 inputs are added with this module.
}

# ============================================================
# MODULE: DATABASE
# ============================================================
module "database" {
  source = "../../modules/database"

  project_name = var.project_name
  environment  = var.environment

  # Database subnet, security-group and engine inputs are added with this module.
}

# ============================================================
# MODULE: COMPUTE
# ============================================================
module "compute" {
  source = "../../modules/compute"

  project_name = var.project_name
  environment  = var.environment

  # Launch template, ASG, target-group, database and log inputs follow later.
}

# ============================================================
# MODULE: MONITORING
# ============================================================
module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  environment  = var.environment

  alb_arn_suffix          = module.alb.load_balancer_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  autoscaling_group_name  = module.compute.autoscaling_group_name
  db_instance_identifier  = module.database.db_instance_identifier

  log_retention_days               = var.log_retention_days
  alarm_actions                    = var.alarm_actions
  alb_5xx_threshold                = var.alb_5xx_threshold
  alb_unhealthy_host_threshold     = var.alb_unhealthy_host_threshold
  asg_cpu_threshold                = var.asg_cpu_threshold
  asg_in_service_threshold         = var.asg_in_service_threshold
  rds_cpu_threshold                = var.rds_cpu_threshold
  rds_free_storage_threshold_bytes = var.rds_free_storage_threshold_bytes
  api_error_count_threshold        = var.api_error_count_threshold
}
