# Root environment variables grouped in the same order as environments/dev/main.tf.
# Variable values and validation rules are unchanged; only their organization is standardized.

# ============================================================
# SHARED ENVIRONMENT CONTEXT
# ============================================================
variable "project_name" {
  description = "Project identifier used in resource names and tags."
  type        = string
  default     = "aws-infra-for-ecommerce"
  nullable    = false
}

variable "environment" {
  description = "Deployment environment identifier."
  type        = string
  default     = "dev"
  nullable    = false
}

variable "aws_region" {
  description = "AWS Region where regional resources are deployed."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

# ============================================================
# MODULE: NETWORK
# ============================================================
variable "vpc_cidr" {
  description = "CIDR block assigned to the VPC."
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "Exactly two Availability Zones for public and database subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  nullable    = false

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must contain exactly two Availability Zones."
  }
}

variable "public_subnet_cidrs" {
  description = "Exactly two CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  nullable    = false

  validation {
    condition = length(var.public_subnet_cidrs) == 2 && alltrue([
      for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "public_subnet_cidrs must contain exactly two valid CIDR blocks."
  }
}

variable "database_subnet_cidrs" {
  description = "Exactly two CIDR blocks for private database subnets."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
  nullable    = false

  validation {
    condition = length(var.database_subnet_cidrs) == 2 && alltrue([
      for cidr in var.database_subnet_cidrs : can(cidrnetmask(cidr))
    ])
    error_message = "database_subnet_cidrs must contain exactly two valid CIDR blocks."
  }
}

# ============================================================
# MODULE: SECURITY GROUPS
# ============================================================
variable "alb_listener_port" {
  description = "HTTP port exposed by the Application Load Balancer to CloudFront."
  type        = number
  default     = 80
  nullable    = false
}

variable "application_port" {
  description = "Port on which the API application accepts traffic from the ALB."
  type        = number
  default     = 3000
  nullable    = false
}

variable "database_port" {
  description = "Port on which the RDS engine accepts connections."
  type        = number
  default     = 5432
  nullable    = false
}

# ============================================================
# MODULE: APPLICATION LOAD BALANCER
# ============================================================
variable "alb_health_check_path" {
  description = "HTTP path the ALB uses to determine application health."
  type        = string
  default     = "/health"
  nullable    = false

  validation {
    condition     = startswith(var.alb_health_check_path, "/")
    error_message = "alb_health_check_path must start with a slash (/)."
  }
}

variable "alb_idle_timeout_seconds" {
  description = "Idle timeout, in seconds, for the ALB."
  type        = number
  default     = 60
  nullable    = false
}

variable "alb_deletion_protection" {
  description = "Whether deletion protection is enabled for the ALB."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_alb_https_test" {
  description = "Whether to create an optional HTTPS listener on the ALB using an imported local certificate."
  type        = bool
  default     = false
  nullable    = false
}

variable "alb_https_certificate_file" {
  description = "Local path to the PEM certificate body for the optional ALB HTTPS test listener."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_alb_https_test || var.alb_https_certificate_file != null
    error_message = "alb_https_certificate_file is required when enable_alb_https_test is true."
  }
}

variable "alb_https_private_key_file" {
  description = "Local path to the PEM private key for the optional ALB HTTPS test listener."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_alb_https_test || var.alb_https_private_key_file != null
    error_message = "alb_https_private_key_file is required when enable_alb_https_test is true."
  }
}

variable "alb_https_certificate_version" {
  description = "Version incremented when the local ALB HTTPS certificate is rotated."
  type        = number
  default     = 1
  nullable    = false
}

variable "alb_https_client_cidr_blocks" {
  description = "Client CIDR blocks allowed to reach the optional ALB HTTPS test listener."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.alb_https_client_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "alb_https_client_cidr_blocks must contain valid CIDR blocks."
  }
}

variable "cloudfront_alb_header_name" {
  description = "Name of the private header CloudFront sends to the ALB origin."
  type        = string
  default     = "X-Origin-Verify"
  nullable    = false
}

variable "cloudfront_alb_header_value" {
  description = "Secret value for the private CloudFront-to-ALB header; supply it outside version control."
  type        = string
  sensitive   = true
  nullable    = false
}

# ============================================================
# MODULE: FRONTEND
# ============================================================
variable "frontend_bucket_force_destroy" {
  description = "Whether frontend bucket objects are deleted automatically with the bucket."
  type        = bool
  default     = false
  nullable    = false
}

variable "cloudfront_price_class" {
  description = "CloudFront price class for the frontend distribution."
  type        = string
  default     = "PriceClass_100"
  nullable    = false

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_100", "PriceClass_200"], var.cloudfront_price_class)
    error_message = "cloudfront_price_class must be PriceClass_All, PriceClass_100 or PriceClass_200."
  }
}

variable "enable_cloudfront_api" {
  description = "Whether CloudFront should route /api/* to the ALB; false for the direct ALB API architecture."
  type        = bool
  default     = false
  nullable    = false
}

variable "cloudfront_alb_origin_protocol_policy" {
  description = "Protocol CloudFront uses to connect to the ALB origin in the dev environment."
  type        = string
  default     = "http-only"
  nullable    = false

  validation {
    condition     = var.cloudfront_alb_origin_protocol_policy == "http-only"
    error_message = "cloudfront_alb_origin_protocol_policy must be http-only for the dev environment."
  }
}

# ============================================================
# MODULE: DATABASE
# ============================================================
variable "database_engine" {
  description = "Database engine for the RDS instance."
  type        = string
  default     = "postgres"
  nullable    = false
}

variable "database_engine_version" {
  description = "Database engine version for the RDS instance."
  type        = string
  default     = "16.4"
  nullable    = false
}

variable "database_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
  nullable    = false
}

variable "database_allocated_storage_gib" {
  description = "Initial RDS allocated storage in GiB."
  type        = number
  default     = 20
  nullable    = false
}

variable "database_max_allocated_storage_gib" {
  description = "Maximum RDS storage autoscaling limit in GiB."
  type        = number
  default     = 100
  nullable    = false
}

variable "database_storage_type" {
  description = "RDS storage type."
  type        = string
  default     = "gp3"
  nullable    = false
}

variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "ecommerce"
  nullable    = false
}

variable "database_username" {
  description = "RDS master username."
  type        = string
  default     = "postgres"
  nullable    = false
}

variable "database_password" {
  description = "RDS master password supplied out-of-band; never commit this value."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "database_secret_arn" {
  description = "Optional ARN of an existing secret for application runtime credentials; it does not configure the RDS master password."
  type        = string
  default     = null
}

variable "database_backup_retention_days" {
  description = "Number of days to retain automated RDS backups."
  type        = number
  default     = 7
  nullable    = false
}

variable "database_deletion_protection" {
  description = "Whether deletion protection is enabled for the RDS instance."
  type        = bool
  default     = false
  nullable    = false
}

variable "database_skip_final_snapshot" {
  description = "Whether to skip the final RDS snapshot when the instance is destroyed."
  type        = bool
  default     = true
  nullable    = false
}

variable "database_final_snapshot_identifier" {
  description = "Optional final snapshot identifier when the final snapshot is enabled."
  type        = string
  default     = null
}

variable "database_backup_window" {
  description = "UTC daily backup window for RDS."
  type        = string
  default     = "03:00-04:00"
  nullable    = false
}

variable "database_maintenance_window" {
  description = "UTC weekly maintenance window for RDS."
  type        = string
  default     = "sun:04:00-sun:05:00"
  nullable    = false
}

variable "database_delete_automated_backups" {
  description = "Whether automated RDS backups are deleted with the instance."
  type        = bool
  default     = true
  nullable    = false
}

variable "database_apply_immediately" {
  description = "Whether RDS modifications are applied immediately."
  type        = bool
  default     = false
  nullable    = false
}

variable "database_auto_minor_version_upgrade" {
  description = "Whether RDS may apply automatic minor engine version upgrades."
  type        = bool
  default     = true
  nullable    = false
}

variable "database_enabled_cloudwatch_logs_exports" {
  description = "RDS engine log types exported to CloudWatch Logs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "database_log_retention_days" {
  description = "Number of days to retain RDS engine logs in CloudWatch Logs."
  type        = number
  default     = 14
  nullable    = false
}

# ============================================================
# MODULE: COMPUTE
# ============================================================
variable "compute_instance_type" {
  description = "EC2 instance type used by the API Auto Scaling Group."
  type        = string
  default     = "t3.micro"
  nullable    = false
}

variable "compute_root_volume_size_gib" {
  description = "Encrypted gp3 root volume size in GiB for API instances."
  type        = number
  default     = 20
  nullable    = false
}

variable "compute_detailed_monitoring" {
  description = "Whether EC2 detailed monitoring is enabled for API instances."
  type        = bool
  default     = false
  nullable    = false
}

variable "compute_min_size" {
  description = "Minimum number of API instances in the Auto Scaling Group."
  type        = number
  default     = 2
  nullable    = false
}

variable "compute_desired_capacity" {
  description = "Desired number of API instances in the Auto Scaling Group."
  type        = number
  default     = 2
  nullable    = false
}

variable "compute_max_size" {
  description = "Maximum number of API instances in the Auto Scaling Group."
  type        = number
  default     = 4
  nullable    = false
}

variable "compute_cpu_target_percent" {
  description = "Average ASG CPU utilization target for target-tracking scaling."
  type        = number
  default     = 60
  nullable    = false
}

variable "compute_health_check_grace_period_seconds" {
  description = "Grace period before the ASG evaluates new instance health."
  type        = number
  default     = 300
  nullable    = false
}

variable "application_docker_image" {
  description = "Docker Hub image URI, including a fixed version tag, for the API container."
  type        = string

  validation {
    condition = trimspace(var.application_docker_image) != "" && !strcontains(var.application_docker_image, " ") && (
      strcontains(var.application_docker_image, ":") || strcontains(var.application_docker_image, "@sha256:")
    )
    error_message = "application_docker_image must be a non-empty image URI without spaces and include a fixed tag or digest."
  }
}

# ============================================================
# MODULE: MONITORING
# ============================================================
variable "log_retention_days" {
  description = "Number of days to retain API and system logs in CloudWatch Logs."
  type        = number
  default     = 14
  nullable    = false

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be a valid CloudWatch Logs retention period."
  }
}

variable "alarm_actions" {
  description = "Optional ARNs of notification targets invoked when an alarm changes state; an empty list disables notifications."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "alb_5xx_threshold" {
  description = "ALB 5XX error count threshold for the alarm evaluation period."
  type        = number
  default     = 10
  nullable    = false
}

variable "alb_unhealthy_host_threshold" {
  description = "Unhealthy target count threshold for the target-group alarm."
  type        = number
  default     = 1
  nullable    = false
}

variable "asg_cpu_threshold" {
  description = "Average CPU utilization percentage that triggers the ASG alarm."
  type        = number
  default     = 80
  nullable    = false
}

variable "asg_in_service_threshold" {
  description = "Minimum in-service instance count before the ASG alarm triggers."
  type        = number
  default     = 1
  nullable    = false
}

variable "rds_cpu_threshold" {
  description = "Average CPU utilization percentage that triggers the RDS alarm."
  type        = number
  default     = 80
  nullable    = false
}

variable "rds_free_storage_threshold_bytes" {
  description = "Free storage threshold in bytes that triggers the RDS alarm."
  type        = number
  default     = 5368709120
  nullable    = false
}

variable "api_error_count_threshold" {
  description = "Application error count threshold extracted from the API log group."
  type        = number
  default     = 10
  nullable    = false
}
