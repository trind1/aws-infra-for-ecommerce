output "autoscaling_group_name" {
  description = "API Auto Scaling Group name."
  value       = aws_autoscaling_group.api.name
}

output "autoscaling_group_arn" {
  description = "API Auto Scaling Group ARN."
  value       = aws_autoscaling_group.api.arn
}

output "launch_template_id" {
  description = "API launch template ID."
  value       = aws_launch_template.api.id
}

output "instance_role_arn" {
  description = "EC2 instance role ARN."
  value       = aws_iam_role.api.arn
}

output "instance_profile_name" {
  description = "EC2 instance profile name."
  value       = aws_iam_instance_profile.api.name
}
