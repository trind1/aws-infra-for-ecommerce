# ============ INTERNET-FACING ALB  ============

resource "aws_lb" "this" {
  name                       = local.alb_name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.security_group_id]
  subnets                    = var.subnet_ids
  enable_deletion_protection = var.enable_deletion_protection
  drop_invalid_header_fields = true
  idle_timeout               = var.idle_timeout

  tags = {
    Name      = local.alb_name
    Component = "alb"
    Tier      = "public"
  }
}

# ============ API TARGET GROUP  ============

resource "aws_lb_target_group" "api" {
  name        = local.target_group_name
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name      = local.target_group_name
    Component = "alb"
    Tier      = "application"
  }
}

# ============ HTTP LISTENER  ============

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  tags = {
    Name      = "${local.alb_name}-listener"
    Component = "alb"
    Tier      = "public"
  }
}

# ============ OPTIONAL HTTPS TEST LISTENER ============

resource "aws_lb_listener" "api_https_test" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.https_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  lifecycle {
    precondition {
      condition     = var.https_certificate_arn != null
      error_message = "https_certificate_arn is required when enable_https_listener is true."
    }
  }

  tags = {
    Name      = "${local.alb_name}-https-test-listener"
    Component = "alb"
    Tier      = "public"
  }
}

# ============ CLOUDFRONT API LISTENER RULE  ============

resource "aws_lb_listener_rule" "api_from_cloudfront" {
  listener_arn = aws_lb_listener.api.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }

  condition {
    http_header {
      http_header_name = var.origin_custom_header_name
      values           = [var.origin_custom_header_value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Name      = "${local.alb_name}-api-rule"
    Component = "alb"
    Tier      = "public"
  }
}

# ============ HTTPS TEST LISTENER RULE  ============

resource "aws_lb_listener_rule" "api_from_https_test" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = aws_lb_listener.api_https_test[0].arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  tags = {
    Name      = "${local.alb_name}-https-test-api-rule"
    Component = "alb"
    Tier      = "public"
  }
}
