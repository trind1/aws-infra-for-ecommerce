# Database module

## Phạm vi

Module tạo database foundation cho một môi trường:

1. Một `aws_db_subnet_group` từ đúng hai private database subnets.
2. Các `aws_cloudwatch_log_group` có tên chuẩn để RDS export engine logs, nếu environment bật log types.
3. Một `aws_db_instance` PostgreSQL/RDS Single-AZ, private và encrypted.

Module không tạo VPC/subnet/security group, Route 53, ACM certificate, Secrets Manager secret, read replica, cluster hoặc Multi-AZ standby.

## Thiết kế bảo mật và lifecycle

- `publicly_accessible = false`: RDS không nhận kết nối trực tiếp từ Internet.
- `multi_az = false`: phạm vi hiện tại là Single-AZ; HA Multi-AZ là quyết định/cải tiến riêng.
- `storage_encrypted = true`: bật encryption cho storage.
- `vpc_security_group_ids` nhận đúng database security group từ composition layer.
- `skip_final_snapshot`, `final_snapshot_identifier` và `deletion_protection` được điều khiển bởi environment để thể hiện criticality.
- `copy_tags_to_snapshot = true` giữ metadata khi tạo snapshot.

## Credential boundary

`username` và `password` là input của module; `password` được đánh dấu `sensitive`. Tuy nhiên, AWS provider có thể ghi giá trị password vào Terraform state khi quản lý `aws_db_instance`. Vì vậy password phải được inject ngoài Git (ví dụ biến môi trường/CI secret) và backend state phải có encryption, access control và audit phù hợp.

Module không đọc hoặc tạo Secrets Manager secret. Nếu application cần `database_secret_arn`, composition layer có thể truyền ARN đó cho module compute ở bước sau; ARN này không tự động cấu hình master password cho RDS.

## Input chính

| Nhóm | Inputs |
|---|---|
| Identity/network | `project_name`, `environment`, `subnet_ids`, `security_group_id` |
| Engine/storage | `engine`, `engine_version`, `instance_class`, `allocated_storage`, `max_allocated_storage`, `storage_type`, `database_name`, `port` |
| Credentials | `username`, `password` |
| Backup/lifecycle | `backup_retention_period`, `backup_window`, `maintenance_window`, `deletion_protection`, `skip_final_snapshot`, `final_snapshot_identifier`, `delete_automated_backups`, `apply_immediately`, `auto_minor_version_upgrade` |
| Observability | `enabled_cloudwatch_logs_exports`, `log_retention_in_days` |

`subnet_ids` phải có chính xác hai phần tử. Module không suy luận subnet từ VPC và không tự tạo security group.

## Output contract

| Output | Consumer |
|---|---|
| `db_instance_arn` | Environment/operations |
| `db_instance_identifier` | Monitoring RDS alarms |
| `db_address`, `db_port` | Compute application configuration |
| `db_endpoint` | Environment/operations |
| `db_subnet_group_name` | Environment/operations/audit |
| `rds_log_group_names` | Environment/operations |

Module không export master username, password hoặc secret value.

## Checklist và evidence

| Hạng mục | Trạng thái | Evidence |
|---|---|---|
| Private DB subnet group | Implemented | `main.tf` → `aws_db_subnet_group.this` |
| Single-AZ encrypted RDS | Implemented | `main.tf` → `aws_db_instance.this` |
| Database SG boundary | Implemented | `vpc_security_group_ids = [var.security_group_id]` |
| Backup/deletion controls | Implemented | RDS lifecycle arguments |
| RDS log exports | Implemented | `aws_cloudwatch_log_group.rds` và `enabled_cloudwatch_logs_exports` |
| Sensitive credential handling | Implemented | `variables.tf` sensitive password; không có password output |
| Stable output contract | Implemented | `outputs.tf` |
| Static validation | Blocked | AWS provider plugin chưa khởi động được trong environment; `terraform fmt` đã chạy |

## Assumptions

- Environment hiện tại chọn PostgreSQL, nhưng module giữ `engine`/`engine_version` là input để tái sử dụng.
- `engine_version` và log export types phải tồn tại trong AWS region thực tế; điều này cần kiểm tra ở plan/provider runtime.
- Database subnets đã được tạo ở module network và database SG đã được tạo ở module security-groups.
