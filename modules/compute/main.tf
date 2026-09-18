# ============ DATA SOURCES  ============

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ============ IAM TRUST POLICY  ============
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# ============ COMPUTE LOCALS  ============
locals {
  name                 = "${var.project_name}-${var.environment}"
  instance_name        = "${local.name}-api"
  role_name            = substr(replace(lower("${local.name}-api-role"), "/[^a-z0-9+=,.@_-]/", "-"), 0, 64)
  instance_profile     = substr(replace(lower("${local.name}-api-profile"), "/[^a-z0-9+=,.@_-]/", "-"), 0, 128)
  api_log_group_arn    = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.api_log_group_name}:*"
  system_log_group_arn = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.system_log_group_name}:*"

  cloudwatch_agent_config = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }
    metrics = {
      namespace = var.metrics_namespace
      append_dimensions = {
        AutoScalingGroupName = "$${aws:AutoScalingGroupName}"
      }
      metrics_collected = {
        mem = {
          measurement                 = ["mem_used_percent"]
          metrics_collection_interval = 60
        }
        disk = {
          resources                   = ["/"]
          measurement                 = ["used_percent"]
          metrics_collection_interval = 60
        }
      }
    }
    logs = {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path       = "/var/log/cloud-init-output.log"
              log_group_name  = var.system_log_group_name
              log_stream_name = "{instance_id}/cloud-init"
            }
          ]
        }
      }
    }
  })
}

# ============ IAM ROLE  ============
resource "aws_iam_role" "api" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name      = local.role_name
    Component = "compute"
    Tier      = "application"
  }
}

# ============ SSM INSTANCE MANAGEMENT  ============
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.api.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ============ CLOUDWATCH IAM POLICY  ============
data "aws_iam_policy_document" "cloudwatch" {
  statement {
    sid       = "WriteContainerAndSystemLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
    resources = [local.api_log_group_arn, local.system_log_group_arn]
  }

  statement {
    sid       = "PublishInstanceMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metrics_namespace]
    }
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "${local.name}-cloudwatch-agent"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

# ============ EC2 INSTANCE PROFILE  ============
resource "aws_iam_instance_profile" "api" {
  name = local.instance_profile
  role = aws_iam_role.api.name

  tags = {
    Name      = local.instance_profile
    Component = "compute"
    Tier      = "application"
  }
}

# ============ EC2 LAUNCH TEMPLATE  ============
resource "aws_launch_template" "api" {
  name                   = "${local.name}-api-template"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  update_default_version = true
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    api_log_group_name            = var.api_log_group_name
    aws_region                    = data.aws_region.current.region
    app_name                      = local.instance_name
    app_port                      = var.app_port
    cloudwatch_agent_config       = local.cloudwatch_agent_config
    docker_image                  = var.docker_image
    api_database_url              = var.api_database_url
    api_session_hmac_secret       = var.api_session_hmac_secret
    api_cors_origin               = var.api_cors_origin
    database_connection_limit     = var.database_connection_limit
    database_pool_timeout_seconds = var.database_pool_timeout_seconds
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.api.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.security_group_id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      delete_on_termination = true
      encrypted             = true
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
    }
  }

  metadata_options {
    http_endpoint          = "enabled"
    http_protocol_ipv6     = "disabled"
    http_tokens            = "required"
    instance_metadata_tags = "disabled"
  }

  monitoring {
    enabled = var.detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = local.instance_name
      Component = "compute"
      Tier      = "application"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name      = "${local.instance_name}-volume"
      Component = "compute"
      Tier      = "application"
    }
  }

  tags = {
    Name      = "${local.name}-api-template"
    Component = "compute"
  }
}

# ============ AUTO SCALING GROUP  ============
resource "aws_autoscaling_group" "api" {
  name                      = "${local.name}-api-asg"
  min_size                  = var.min_size
  desired_capacity          = var.desired_capacity
  max_size                  = var.max_size
  vpc_zone_identifier       = var.subnet_ids
  target_group_arns         = [var.target_group_arn]
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  launch_template {
    id      = aws_launch_template.api.id
    version = aws_launch_template.api.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.health_check_grace_period
      skip_matching          = true
    }
  }

  dynamic "tag" {
    for_each = {
      Name      = local.instance_name
      Component = "compute"
      Tier      = "application"
    }

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# ============ CPU TARGET TRACKING  ============
resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.name}-api-cpu-target"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.api.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_value
  }
}
