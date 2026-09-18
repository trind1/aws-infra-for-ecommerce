# Compute module

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 7
- Validated: 0
- Blocked: 1
- Not in scope: 0

## Phạm vi

Module tạo runtime cho NodeJS API trên EC2:

1. IAM role, instance profile và các quyền runtime cần thiết.
2. Một EC2 Launch Template với IMDSv2, public IPv4 và encrypted gp3 root volume.
3. Một Auto Scaling Group trải trên các public subnets, gắn vào ALB target group.
4. Một CPU target-tracking policy và rolling instance refresh.

Bootstrap nằm trong `user_data.sh.tftpl`: cài Docker, pull image, chạy container và cấu hình CloudWatch Agent. Module không tạo VPC, subnet, security group, ALB target group, database, log groups hoặc pipeline build artifact.

## Resources và quyền

| Nhóm | Resource/data | Mục đích |
|---|---|---|
| Identity | `aws_iam_role.api`, `aws_iam_instance_profile.api` | EC2 assume role và profile gắn với Launch Template. |
| Operations | `aws_iam_role_policy_attachment.ssm` | Quản trị instance qua SSM, không cần SSH. |
| Observability | `aws_iam_role_policy.cloudwatch` | Docker `awslogs` ghi container logs và CloudWatch Agent ghi system logs/publish metrics. |
| EC2 | `aws_launch_template.api` | AMI, network interface, user data, IMDSv2, monitoring và EBS. |
| Scaling | `aws_autoscaling_group.api`, `aws_autoscaling_policy.cpu` | Capacity, ALB registration, health và CPU scaling. |

## Network và bảo mật

- ASG chạy trong public subnets theo kiến trúc hiện tại và instance nhận public IPv4 để bootstrap qua Internet Gateway.
- Launch Template chỉ gắn application security group; ingress application port do SG module giới hạn từ ALB SG.
- Không có SSH ingress hoặc key pair path; SSM là kênh quản trị.
- `http_tokens = "required"` bắt buộc IMDSv2.
- Root EBS dùng `encrypted = true`, `volume_type = "gp3"` và xóa cùng instance.
- User data nhận runtime `DATABASE_URL` và `SESSION_HMAC_SECRET`; không ghi các giá trị này
  vào log hoặc output.

## Bootstrap contract

User data cài Docker, pull `docker_image` và publish host port `app_port` vào container.
Container phải listen trên `0.0.0.0:<app_port>` và cung cấp health endpoint theo contract
của ALB.

Docker `awslogs` gửi stdout/stderr của container tới `api_log_group_name` với stream
`<app_name>/<hostname>`. Log group phải tồn tại trước bootstrap; vì vậy Docker dùng
`awslogs-create-group=false`.

CloudWatch Agent chỉ gửi `cloud-init-output.log` tới `system_log_group_name` và memory/disk
metrics tới `metrics_namespace`. Hai cơ chế này không đọc cùng một nguồn log.

## Input chính

| Nhóm | Inputs |
|---|---|
| Identity | `project_name`, `environment` |
| EC2 | `ami_id`, `instance_type`, `root_volume_size`, `detailed_monitoring` |
| Network/ALB | `subnet_ids`, `security_group_id`, `target_group_arn`, `app_port` |
| Scaling | `min_size`, `desired_capacity`, `max_size`, `cpu_target_value`, `health_check_grace_period` |
| Docker/bootstrap | `docker_image`, `app_port` |
| Observability | `api_log_group_name`, `system_log_group_name`, `metrics_namespace` |
| API runtime | `api_database_url`, `api_session_hmac_secret`, `api_cors_origin` |
| Database pool | `database_connection_limit`, `database_pool_timeout_seconds` |

Không có `tags` input; common tags do provider `default_tags` quản lý, module chỉ thêm `Name`, `Component` và `Tier` riêng cho resource/tag propagation.

## Output contract

| Output | Consumer |
|---|---|
| `autoscaling_group_name` | Monitoring ASG alarms |
| `autoscaling_group_arn` | Environment/operations |
| `launch_template_id` | Environment/operations |
| `instance_role_arn` | Environment/operations/audit |
| `instance_profile_name` | Environment/operations/audit |

Module không output user data, password, secret value hoặc IAM policy document tổng thể.

## Checklist và evidence

| Hạng mục | Trạng thái | Evidence |
|---|---|---|
| IAM role/profile | Implemented | `main.tf:69`, `main.tf:135` → IAM resources |
| Least-privilege SSM/logs/metrics permissions | Implemented | `main.tf:81`, `main.tf:87`, `main.tf:109` → policy documents |
| Launch Template security settings | Implemented | `main.tf:147` → `aws_launch_template.api` |
| User data Docker bootstrap và `awslogs` | Implemented | `user_data.sh.tftpl:1`, `user_data.sh.tftpl:29` |
| Auto Scaling Group và ALB registration | Implemented | `main.tf:223` → `aws_autoscaling_group.api` |
| CPU scaling và instance refresh | Implemented | `main.tf:238`, `main.tf:268` → ASG policy/refresh |
| Stable outputs | Implemented | `outputs.tf:1` |
| Static/security validation | Blocked | `fmt` pass; provider schema validate blocked; scanners chưa cài |

## Assumptions

- Environment phải cung cấp AMI hợp lệ trong `aws_region`; module không tự tìm AMI.
- AMI phải có SSM Agent đang chạy hoặc có cơ chế cài/khởi động agent; module chỉ cấp IAM permission.
- ALB target group đã tồn tại và có health check path tương thích với API.
- Monitoring log groups đã tồn tại trước bootstrap.
- `api_database_url` và `api_session_hmac_secret` được truyền sensitive từ composition; chúng
  vẫn có thể xuất hiện trong Terraform state và launch template user data.
