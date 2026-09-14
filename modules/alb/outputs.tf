output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS name used by CloudFront."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB Route 53 zone ID."
  value       = aws_lb.this.zone_id
}

output "target_group_arn" {
  description = "API target group ARN."
  value       = aws_lb_target_group.api.arn
}

output "target_group_arn_suffix" {
  description = "API target group ARN suffix for CloudWatch dimensions."
  value       = aws_lb_target_group.api.arn_suffix
}

output "load_balancer_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch dimensions."
  value       = aws_lb.this.arn_suffix
}

output "listener_arn" {
  description = "API listener ARN."
  value       = aws_lb_listener.api.arn
}

output "listener_port" {
  description = "Effective ALB listener port."
  value       = aws_lb_listener.api.port
}
