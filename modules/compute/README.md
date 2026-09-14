# Compute module

Tạo IAM role/instance profile, Launch Template và duy nhất một ASG cho NodeJS API. ASG chạy tối thiểu 2 instance trên hai public subnet, có CPU target tracking, IMDSv2 bắt buộc, public IPv4 để outbound qua IGW, EBS gp3 mã hóa và không mở SSH.

Bootstrap cài NodeJS, systemd service, CloudWatch Agent và endpoint health-only tối thiểu nếu chưa có artifact. Có thể truyền ZIP qua `api_artifact_s3_bucket/key`; role chỉ được `s3:GetObject` đúng object đó. Ứng dụng thật nhận DB endpoint/user và tùy chọn Secrets Manager ARN, không đưa password vào user data. SSM policy cho phép quản trị không cần SSH.

| Input chính | Output chính |
|---|---|
| `ami_id`, `instance_type`, ASG sizes | `autoscaling_group_name`, `autoscaling_group_arn` |
| `target_group_arn`, `app_port` | `launch_template_id` |
| log group names, artifact/secret tùy chọn | instance role/profile |
