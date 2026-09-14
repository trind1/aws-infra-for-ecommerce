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

variable "api_artifact_s3_bucket" {
  description = "Optional S3 bucket containing a ZIP of the NodeJS API."
  type        = string
  default     = null
}

variable "api_artifact_s3_key" {
  description = "Optional S3 object key for the NodeJS API ZIP."
  type        = string
  default     = null
}

variable "api_start_command" {
  description = "Systemd ExecStart command for the API artifact."
  type        = string
  default     = "/usr/bin/node /opt/nodejs-api/server.js"
}

variable "api_log_file" {
  description = "Application log filename under /var/log/<app-name>."
  type        = string
  default     = "application.log"
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

variable "database_host" {
  description = "RDS endpoint supplied to the API without a password."
  type        = string
}

variable "database_port" {
  description = "RDS port supplied to the API."
  type        = number
}

variable "database_name" {
  description = "Optional database name supplied to the API."
  type        = string
  default     = ""
}

variable "database_username" {
  description = "Database username supplied to the API."
  type        = string
}

variable "database_credentials_secret_arn" {
  description = "Optional Secrets Manager ARN read by the API for the database password."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags applied to taggable compute resources."
  type        = map(string)
  default     = {}
}
