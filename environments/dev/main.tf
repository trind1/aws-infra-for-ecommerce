locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }

  monitoring_name  = "${var.project_name}-${var.environment}"
  compute_asg_name = "${local.monitoring_name}-api-asg"
}

# AWS maintains this prefix list in the current provider region.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Amazon Linux 2023 x86_64 AMI published by AWS for the current region.
# The compute bootstrap installs the amd64 CloudWatch Agent package.
data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
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
  cloudfront_origin_prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id
  alb_listener_port                = var.alb_listener_port
  application_port                 = var.application_port
  database_port                    = var.database_port

  # Common tags are applied by the provider default_tags configuration.
}

# ============================================================
# MODULE: APPLICATION LOAD BALANCER
# ============================================================
module "alb" {
  source = "../../modules/alb"

  project_name = var.project_name
  environment  = var.environment

  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id

  target_port       = var.application_port
  health_check_path = var.alb_health_check_path
  listener_port     = var.alb_listener_port

  origin_custom_header_name  = var.cloudfront_alb_header_name
  origin_custom_header_value = var.cloudfront_alb_header_value

  enable_deletion_protection = var.alb_deletion_protection
  idle_timeout               = var.alb_idle_timeout_seconds
}

# ============================================================
# MODULE: FRONTEND
# ============================================================
module "frontend" {
  source = "../../modules/frontend"

  project_name = var.project_name
  environment  = var.environment

  alb_origin_dns_name        = module.alb.alb_dns_name
  alb_origin_protocol_policy = var.cloudfront_alb_origin_protocol_policy

  cloudfront_aliases         = []
  cloudfront_certificate_arn = null
  cloudfront_price_class     = var.cloudfront_price_class

  origin_custom_header_name  = var.cloudfront_alb_header_name
  origin_custom_header_value = var.cloudfront_alb_header_value
  bucket_force_destroy       = var.frontend_bucket_force_destroy
}

# ============================================================
# MODULE: DATABASE
# ============================================================
module "database" {
  source = "../../modules/database"

  project_name = var.project_name
  environment  = var.environment

  subnet_ids        = module.network.database_subnet_ids
  security_group_id = module.security_groups.database_security_group_id

  engine                = var.database_engine
  engine_version        = var.database_engine_version
  instance_class        = var.database_instance_class
  allocated_storage     = var.database_allocated_storage_gib
  max_allocated_storage = var.database_max_allocated_storage_gib
  storage_type          = var.database_storage_type
  database_name         = var.database_name
  username              = var.database_username
  password              = var.database_password
  port                  = var.database_port

  backup_retention_period    = var.database_backup_retention_days
  backup_window              = var.database_backup_window
  maintenance_window         = var.database_maintenance_window
  deletion_protection        = var.database_deletion_protection
  skip_final_snapshot        = var.database_skip_final_snapshot
  final_snapshot_identifier  = var.database_final_snapshot_identifier
  delete_automated_backups   = var.database_delete_automated_backups
  apply_immediately          = var.database_apply_immediately
  auto_minor_version_upgrade = var.database_auto_minor_version_upgrade

  enabled_cloudwatch_logs_exports = var.database_enabled_cloudwatch_logs_exports
  log_retention_in_days           = var.database_log_retention_days
}

# ============================================================
# MODULE: COMPUTE
# ============================================================
module "compute" {
  source = "../../modules/compute"

  project_name = var.project_name
  environment  = var.environment

  ami_id                    = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type             = var.compute_instance_type
  subnet_ids                = module.network.public_subnet_ids
  security_group_id         = module.security_groups.application_security_group_id
  target_group_arn          = module.alb.target_group_arn
  app_port                  = var.application_port
  root_volume_size          = var.compute_root_volume_size_gib
  detailed_monitoring       = var.compute_detailed_monitoring
  min_size                  = var.compute_min_size
  desired_capacity          = var.compute_desired_capacity
  max_size                  = var.compute_max_size
  cpu_target_value          = var.compute_cpu_target_percent
  health_check_grace_period = var.compute_health_check_grace_period_seconds

  api_artifact_s3_bucket = var.application_artifact_bucket
  api_artifact_s3_key    = var.application_artifact_key
  api_start_command      = var.application_start_command
  api_log_file           = var.application_log_file

  api_log_group_name    = module.monitoring.api_log_group_name
  system_log_group_name = module.monitoring.system_log_group_name
  metrics_namespace     = module.monitoring.metric_namespace

  database_host                   = module.database.db_address
  database_port                   = module.database.db_port
  database_name                   = var.database_name
  database_username               = var.database_username
  database_credentials_secret_arn = var.database_secret_arn
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
  autoscaling_group_name  = local.compute_asg_name
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
