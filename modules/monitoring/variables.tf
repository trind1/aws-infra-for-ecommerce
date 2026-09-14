variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in resource names."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix for ApplicationELB metric dimensions."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix for ApplicationELB metric dimensions."
  type        = string
}

variable "autoscaling_group_name" {
  description = "API Auto Scaling Group name for EC2/Auto Scaling metric dimensions."
  type        = string
}

variable "db_instance_identifier" {
  description = "RDS instance identifier for metric dimensions."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for API and system log groups."
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

variable "alb_5xx_threshold" {
  description = "ALB ELB-side 5XX count threshold per five-minute period."
  type        = number
  default     = 10
  nullable    = false
}

variable "alb_unhealthy_host_threshold" {
  description = "Unhealthy target count threshold for the ALB alarm."
  type        = number
  default     = 1
  nullable    = false
}

variable "asg_cpu_threshold" {
  description = "ASG average CPU alarm threshold percentage."
  type        = number
  default     = 80
  nullable    = false
}

variable "asg_in_service_threshold" {
  description = "Minimum number of in-service API instances before alarming."
  type        = number
  default     = 1
  nullable    = false
}

variable "rds_cpu_threshold" {
  description = "RDS average CPU alarm threshold percentage."
  type        = number
  default     = 80
  nullable    = false
}

variable "rds_free_storage_threshold_bytes" {
  description = "RDS free storage alarm threshold in bytes."
  type        = number
  default     = 5368709120
  nullable    = false
}

variable "api_error_count_threshold" {
  description = "Application error log count threshold per five-minute period."
  type        = number
  default     = 10
  nullable    = false
}

variable "alarm_actions" {
  description = "Optional SNS or other alarm action ARNs."
  type        = list(string)
  default     = []
  nullable    = false
}
