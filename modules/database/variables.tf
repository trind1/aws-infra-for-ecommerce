variable "project_name" {
  description = "Project identifier used in database names."
  type        = string
}

variable "environment" {
  description = "Environment identifier used in database names."
  type        = string
}

variable "subnet_ids" {
  description = "Exactly two private database subnet IDs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) == 2
    error_message = "subnet_ids must contain exactly two private database subnets."
  }
}

variable "security_group_id" {
  description = "RDS security group ID."
  type        = string
}

variable "engine" {
  description = "RDS engine identifier, for example mysql or postgres."
  type        = string
}

variable "engine_version" {
  description = "Optional engine version; set explicitly when the environment requires a pinned version."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB."
  type        = number
}

variable "max_allocated_storage" {
  description = "Maximum storage autoscaling size in GiB; 0 disables storage autoscaling."
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "RDS storage type."
  type        = string
  default     = "gp3"
}

variable "database_name" {
  description = "Optional initial database name."
  type        = string
  default     = ""
}

variable "username" {
  description = "Master database username."
  type        = string
}

variable "password" {
  description = "Master database password supplied out-of-band."
  type        = string
  sensitive   = true
}

variable "port" {
  description = "Database listener port."
  type        = number
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
}

variable "backup_window" {
  description = "UTC daily backup window."
  type        = string
}

variable "maintenance_window" {
  description = "UTC weekly maintenance window."
  type        = string
}

variable "deletion_protection" {
  description = "Protect RDS from deletion."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip a final snapshot on destroy; use true only for disposable environments."
  type        = bool
}

variable "final_snapshot_identifier" {
  description = "Optional final snapshot identifier when skip_final_snapshot is false."
  type        = string
  default     = null
}

variable "delete_automated_backups" {
  description = "Delete automated backups when the DB is deleted."
  type        = bool
}

variable "apply_immediately" {
  description = "Apply modifications immediately instead of waiting for the maintenance window."
  type        = bool
}

variable "auto_minor_version_upgrade" {
  description = "Allow automatic minor engine version upgrades."
  type        = bool
}

variable "enabled_cloudwatch_logs_exports" {
  description = "RDS engine log types exported to CloudWatch Logs."
  type        = list(string)
  default     = []
}

variable "log_retention_in_days" {
  description = "Retention for RDS engine log groups."
  type        = number
  default     = 30
}
