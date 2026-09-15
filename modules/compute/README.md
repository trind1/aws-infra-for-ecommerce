# Compute module

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 8
- Validated: 0
- Blocked: 1
- Not in scope: 0

## Phạm vi

Module tạo runtime cho NodeJS API trên EC2:

1. IAM role, instance profile và các quyền runtime cần thiết.
2. Một EC2 Launch Template với IMDSv2, public IPv4 và encrypted gp3 root volume.
3. Một Auto Scaling Group trải trên các public subnets, gắn vào ALB target group.
4. Một CPU target-tracking policy và rolling instance refresh.

Bootstrap nằm trong `user_data.sh.tftpl`: cài runtime, tải artifact tùy chọn, tạo systemd service và cấu hình CloudWatch Agent. Module không tạo VPC, subnet, security group, ALB target group, database, log groups hoặc pipeline build artifact.

## Resources và quyền

| Nhóm | Resource/data | Mục đích |
|---|---|---|
| Identity | `aws_iam_role.api`, `aws_iam_instance_profile.api` | EC2 assume role và profile gắn với Launch Template. |
| Operations | `aws_iam_role_policy_attachment.ssm` | Quản trị instance qua SSM, không cần SSH. |
| Observability | `aws_iam_role_policy.cloudwatch` | Ghi application/system logs và publish metric namespace đã chỉ định. |
| Artifact | `aws_iam_role_policy.artifact` | Optional `s3:GetObject` đúng object bucket/key. |
| Database secret | `aws_iam_role_policy.database_secret` | Optional đọc secret ARN đã chỉ định ở runtime. |
| EC2 | `aws_launch_template.api` | AMI, network interface, user data, IMDSv2, monitoring và EBS. |
| Scaling | `aws_autoscaling_group.api`, `aws_autoscaling_policy.cpu` | Capacity, ALB registration, health và CPU scaling. |

## Network và bảo mật

- ASG chạy trong public subnets theo kiến trúc hiện tại và instance nhận public IPv4 để bootstrap qua Internet Gateway.
- Launch Template chỉ gắn application security group; ingress application port do SG module giới hạn từ ALB SG.
- Không có SSH ingress hoặc key pair path; SSM là kênh quản trị.
- `http_tokens = "required"` bắt buộc IMDSv2.
- Root EBS dùng `encrypted = true`, `volume_type = "gp3"` và xóa cùng instance.
- User data chỉ nhận DB host/port/name/user và secret ARN; không truyền database password.

## Bootstrap contract

Nếu có `api_artifact_s3_bucket` và `api_artifact_s3_key`, user data tải ZIP đúng object rồi cài production dependencies. Nếu thiếu một trong hai, module tạo health-only fallback phục vụ `/health` và `/api/health`; fallback không phải ứng dụng production.

Systemd chạy command từ `api_start_command`. CloudWatch Agent gửi:

- API log file tới `api_log_group_name`.
- `cloud-init-output.log` tới `system_log_group_name`.
- Memory/disk metrics tới `metrics_namespace`.

## Input chính

| Nhóm | Inputs |
|---|---|
| Identity | `project_name`, `environment` |
| EC2 | `ami_id`, `instance_type`, `root_volume_size`, `detailed_monitoring` |
| Network/ALB | `subnet_ids`, `security_group_id`, `target_group_arn`, `app_port` |
| Scaling | `min_size`, `desired_capacity`, `max_size`, `cpu_target_value`, `health_check_grace_period` |
| Artifact/bootstrap | `api_artifact_s3_bucket`, `api_artifact_s3_key`, `api_start_command`, `api_log_file` |
| Observability | `api_log_group_name`, `system_log_group_name`, `metrics_namespace` |
| Database runtime | `database_host`, `database_port`, `database_name`, `database_username`, `database_credentials_secret_arn` |

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
| IAM role/profile | Implemented | `main.tf:74`, `main.tf:159` → IAM resources |
| Least-privilege SSM/logs/metrics permissions | Implemented | `main.tf:86`, `main.tf:92`, `main.tf:114` → policy documents |
| Optional artifact/secret permissions | Implemented | `main.tf:132`, `main.tf:151` → counted policies |
| Launch Template security settings | Implemented | `main.tf:171` → `aws_launch_template.api` |
| User data bootstrap | Implemented | `user_data.sh.tftpl:1` |
| Auto Scaling Group và ALB registration | Implemented | `main.tf:249` → `aws_autoscaling_group.api` |
| CPU scaling và instance refresh | Implemented | `main.tf:264`, `main.tf:295` → ASG policy/refresh |
| Stable outputs | Implemented | `outputs.tf:1` |
| Static/security validation | Blocked | `fmt` pass; provider schema validate blocked; scanners chưa cài |

## Assumptions

- Environment phải cung cấp AMI hợp lệ trong `aws_region`; module không tự tìm AMI.
- AMI phải có SSM Agent đang chạy hoặc có cơ chế cài/khởi động agent; module chỉ cấp IAM permission.
- ALB target group đã tồn tại và có health check path tương thích với API.
- Monitoring log groups đã tồn tại trước bootstrap.
- Secret ARN, nếu có, là ARN của secret mà application có schema đọc được; module không tạo secret.
