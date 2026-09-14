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

output "alarm_arns" {
  description = "Map of CloudWatch alarm ARNs keyed by monitored signal."
  value = {
    alb_5xx            = aws_cloudwatch_metric_alarm.alb_5xx.arn
    alb_unhealthy_host = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.arn
    asg_cpu            = aws_cloudwatch_metric_alarm.asg_cpu.arn
    asg_in_service     = aws_cloudwatch_metric_alarm.asg_in_service.arn
    rds_cpu            = aws_cloudwatch_metric_alarm.rds_cpu.arn
    rds_free_storage   = aws_cloudwatch_metric_alarm.rds_free_storage.arn
    api_errors         = aws_cloudwatch_metric_alarm.api_errors.arn
  }
}

output "alarm_names" {
  description = "Map of CloudWatch alarm names keyed by monitored signal."
  value = {
    alb_5xx            = aws_cloudwatch_metric_alarm.alb_5xx.alarm_name
    alb_unhealthy_host = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.alarm_name
    asg_cpu            = aws_cloudwatch_metric_alarm.asg_cpu.alarm_name
    asg_in_service     = aws_cloudwatch_metric_alarm.asg_in_service.alarm_name
    rds_cpu            = aws_cloudwatch_metric_alarm.rds_cpu.alarm_name
    rds_free_storage   = aws_cloudwatch_metric_alarm.rds_free_storage.alarm_name
    api_errors         = aws_cloudwatch_metric_alarm.api_errors.alarm_name
  }
}
