output "api_log_group_name" {
  description = "CloudWatch Logs group for NodeJS application logs."
  value       = aws_cloudwatch_log_group.api.name
}

output "system_log_group_name" {
  description = "CloudWatch Logs group for bootstrap/system logs."
  value       = aws_cloudwatch_log_group.system.name
}

output "metric_namespace" {
  description = "Custom CloudWatch namespace used by the CloudWatch Agent."
  value       = local.metric_namespace
}
