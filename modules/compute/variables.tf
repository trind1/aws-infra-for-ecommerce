variable "project_name" {
  description = "Project identifier used in compute names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in compute names."
  type        = string
}

variable "ami_id" {
  description = "AMI ID selected by the environment root module."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the API ASG."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs across two Availability Zones."
  type        = list(string)
}

variable "security_group_id" {
  description = "API EC2 security group ID."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group receiving API instances."
  type        = string
}

variable "app_port" {
  description = "Port on which NodeJS listens."
  type        = number
}

variable "min_size" {
  description = "Minimum API instance count."
  type        = number
}

variable "desired_capacity" {
  description = "Desired API instance count."
  type        = number
}

variable "max_size" {
  description = "Maximum API instance count."
  type        = number
}

variable "cpu_target_value" {
  description = "ASG target tracking CPU percentage."
  type        = number
}

variable "root_volume_size" {
  description = "Encrypted gp3 root volume size in GiB."
  type        = number
}

variable "detailed_monitoring" {
  description = "Enable one-minute EC2 detailed monitoring."
  type        = bool
  default     = false
}

variable "health_check_grace_period" {
  description = "Seconds to allow an instance to bootstrap before ELB health checks count."
  type        = number
  default     = 300
}

variable "docker_image" {
  description = "Docker Hub image URI, including a version tag, used by the API container."
  type        = string

  validation {
    condition = trimspace(var.docker_image) != "" && !strcontains(var.docker_image, " ") && (
      strcontains(var.docker_image, ":") || strcontains(var.docker_image, "@sha256:")
    )
    error_message = "docker_image must be a non-empty image URI without spaces and include a fixed tag or digest."
  }
}

variable "api_log_group_name" {
  description = "CloudWatch Logs group for NodeJS application logs."
  type        = string
}

variable "system_log_group_name" {
  description = "CloudWatch Logs group for bootstrap/system logs."
  type        = string
}

variable "metrics_namespace" {
  description = "CloudWatch custom namespace for memory and disk metrics."
  type        = string
}

variable "api_database_url" {
  description = "Complete PostgreSQL connection URL supplied to the API at runtime."
  type        = string
  sensitive   = true
}

variable "api_session_hmac_secret" {
  description = "HMAC secret used by the API to sign sessions."
  type        = string
  sensitive   = true
}

variable "api_cors_origin" {
  description = "Browser origin allowed by the API CORS policy."
  type        = string
}

variable "database_connection_limit" {
  description = "Maximum number of database connections used by the API."
  type        = number
  default     = 5

  validation {
    condition     = var.database_connection_limit > 0
    error_message = "database_connection_limit must be greater than zero."
  }
}

variable "database_pool_timeout_seconds" {
  description = "Database pool wait timeout in seconds used by the API."
  type        = number
  default     = 10

  validation {
    condition     = var.database_pool_timeout_seconds > 0
    error_message = "database_pool_timeout_seconds must be greater than zero."
  }
}
