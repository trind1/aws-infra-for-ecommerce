variable "project_name" {
  description = "Project identifier used in monitoring names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in monitoring names."
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

variable "log_retention_in_days" {
  description = "Retention for NodeJS and bootstrap log groups."
  type        = number
  default     = 30
}

variable "alb_5xx_threshold" {
  description = "ALB ELB-side 5xx count threshold per five-minute period."
  type        = number
  default     = 10
}

variable "asg_cpu_alarm_threshold" {
  description = "ASG average CPU alarm threshold percentage."
  type        = number
  default     = 80
}

variable "minimum_in_service_instances" {
  description = "Minimum number of in-service API instances before alarming."
  type        = number
  default     = 2
}

variable "rds_cpu_alarm_threshold" {
  description = "RDS average CPU alarm threshold percentage."
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold_bytes" {
  description = "RDS free storage alarm threshold in bytes."
  type        = number
  default     = 5368709120
}

variable "api_error_alarm_threshold" {
  description = "Application error log count threshold per five-minute period."
  type        = number
  default     = 1
}

variable "alarm_actions" {
  description = "Optional SNS or other alarm action ARNs."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to taggable monitoring resources."
  type        = map(string)
  default     = {}
}
