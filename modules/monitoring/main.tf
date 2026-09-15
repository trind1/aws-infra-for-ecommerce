locals {
  name                  = "${var.project_name}-${var.environment}"
  api_log_group_name    = "/aws/${local.name}/api"
  system_log_group_name = "/aws/${local.name}/system"
  metric_namespace      = "${local.name}/API"
  alarm_actions_enabled = length(var.alarm_actions) > 0
}

# ============ CLOUDWATCH LOG GROUPS  ============

resource "aws_cloudwatch_log_group" "api" {
  name              = local.api_log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name      = "${local.name}-api-logs"
    Component = "monitoring"
    Tier      = "application"
  }
}

resource "aws_cloudwatch_log_group" "system" {
  name              = local.system_log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name      = "${local.name}-system-logs"
    Component = "monitoring"
    Tier      = "application"
  }
}

# ============ ALB METRIC ALARMS  ============

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  alarm_description   = "ALB is returning elevated 5xx responses."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  unit                = "Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.alb_5xx_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${local.name}-alb-unhealthy-hosts"
  alarm_description   = "API target group has unhealthy hosts."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  unit                = "Count"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.alb_unhealthy_host_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

# ============ AUTOSCALING METRIC ALARMS  ============

resource "aws_cloudwatch_metric_alarm" "asg_cpu" {
  alarm_name          = "${local.name}-asg-cpu"
  alarm_description   = "API Auto Scaling Group average CPU is high."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  unit                = "Percent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.asg_cpu_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  dimensions = {
    AutoScalingGroupName = var.autoscaling_group_name
  }
}

resource "aws_cloudwatch_metric_alarm" "asg_in_service" {
  alarm_name          = "${local.name}-asg-in-service"
  alarm_description   = "API Auto Scaling Group has fewer instances in service than expected."
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  unit                = "Count"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.asg_in_service_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  dimensions = {
    AutoScalingGroupName = var.autoscaling_group_name
  }
}

# ============ RDS METRIC ALARMS  ============

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu"
  alarm_description   = "RDS CPU utilization is high."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  unit                = "Percent"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.rds_cpu_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${local.name}-rds-free-storage"
  alarm_description   = "RDS free storage is below the configured byte threshold."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  unit                = "Bytes"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.rds_free_storage_threshold_bytes
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }
}

# ============ APPLICATION ERROR METRIC  ============

resource "aws_cloudwatch_log_metric_filter" "api_errors" {
  name           = "${local.name}-api-errors"
  log_group_name = aws_cloudwatch_log_group.api.name
  pattern        = "?ERROR ?Error ?error"

  metric_transformation {
    name          = "ApplicationErrors"
    namespace     = local.metric_namespace
    value         = "1"
    default_value = 0
  }
}

resource "aws_cloudwatch_metric_alarm" "api_errors" {
  alarm_name          = "${local.name}-api-errors"
  alarm_description   = "NodeJS application log contains error entries."
  namespace           = local.metric_namespace
  metric_name         = "ApplicationErrors"
  unit                = "Count"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.api_error_count_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  actions_enabled     = local.alarm_actions_enabled
  alarm_actions       = var.alarm_actions

  depends_on = [aws_cloudwatch_log_metric_filter.api_errors]
}
