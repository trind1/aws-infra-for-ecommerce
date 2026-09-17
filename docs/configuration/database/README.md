# Kế hoạch cấu hình: database

## Mục tiêu

Cung cấp một Amazon RDS PostgreSQL private, Single-AZ cho application tier. Database nằm trong đúng hai database subnets do `network` xuất ra, sử dụng database security group do `security-groups` quản lý và không mở truy cập trực tiếp từ Internet.

Module chỉ quản lý database foundation và connection metadata. Module không tạo Route 53, Secrets Manager secret, read replica, cluster hoặc Multi-AZ standby.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| RDS DB subnet group | Một subnet group gồm đúng hai private database subnet IDs, thường thuộc hai AZ khác nhau. |
| Amazon RDS instance | Một instance PostgreSQL; `publicly_accessible = false`, `multi_az = false`, storage encrypted và chỉ gắn database security group. |
| CloudWatch Logs | Tạo log groups cho các engine log exports được chọn; retention do environment truyền vào. |
| Backup and recovery | Backup retention, backup window, maintenance window, final snapshot, deletion protection và automated-backup cleanup được cấu hình rõ ở environment. |
| Credentials | Master username/password nhận từ input out-of-band. Password là sensitive nhưng vẫn có thể nằm trong Terraform state; không commit vào Git. |

## Phân cấp cấu hình

```text
network.database_subnet_ids
  └── database.aws_db_subnet_group.this

security-groups.database_security_group_id
  └── database.aws_db_instance.this

database.aws_db_instance.this
  ├── compute: db address, port, name và credential reference
  └── monitoring: db instance identifier
```

## Input contract

| Input | Nguồn | Mục đích |
|---|---|---|
| `project_name`, `environment` | Environment | Tạo tên ổn định cho subnet group, instance và log groups. |
| `subnet_ids` | `module.network.database_subnet_ids` | Đặt RDS vào database subnets; module yêu cầu đúng hai IDs. |
| `security_group_id` | `module.security_groups.database_security_group_id` | Giới hạn ingress tới database port theo database SG. |
| `engine`, `engine_version`, `instance_class` | Environment | Chọn engine, version và kích thước RDS. |
| `allocated_storage`, `max_allocated_storage`, `storage_type` | Environment | Cấu hình storage ban đầu, autoscaling và loại volume. |
| `database_name`, `username`, `password`, `port` | Environment/secret injection | Bootstrap database và connection settings; không xuất password. |
| `backup_retention_period`, `backup_window`, `maintenance_window` | Environment | Chính sách backup và maintenance theo môi trường. |
| `deletion_protection`, `skip_final_snapshot`, `final_snapshot_identifier` | Environment | Kiểm soát blast radius khi thay đổi hoặc hủy instance. |
| `delete_automated_backups`, `apply_immediately`, `auto_minor_version_upgrade` | Environment | Kiểm soát lifecycle và thời điểm áp dụng thay đổi. |
| `enabled_cloudwatch_logs_exports`, `log_retention_in_days` | Environment | Chọn loại log RDS export và thời gian lưu. |

`database_secret_arn` ở composition layer là credential reference dành cho application runtime/compute. Nó không tự động cấp master password cho RDS; việc đọc secret theo schema cụ thể chưa thuộc phạm vi module này.

## Output contract

| Output | Consumer | Ý nghĩa |
|---|---|---|
| `db_instance_arn` | Environment/operations | ARN của RDS instance. |
| `db_instance_identifier` | `monitoring` | Identity để tạo RDS CloudWatch alarms. |
| `db_address` | `compute` | DNS address của RDS, không kèm port. |
| `db_endpoint` | Environment/operations | Endpoint có cả address và port theo AWS provider. |
| `db_port` | `compute`, environment | Port kết nối tới RDS. |
| `db_subnet_group_name` | Environment/operations | Evidence về subnet group đang được RDS sử dụng. |
| `rds_log_group_names` | Environment/operations | Map engine log type → CloudWatch log group name. |

Password, master username và giá trị secret không được expose qua output.

## Checklist triển khai

| Hạng mục | Trạng thái | Evidence cần kiểm tra |
|---|---|---|
| Database subnet group | Implemented | `modules/database/main.tf`, `aws_db_subnet_group.this` |
| RDS private Single-AZ | Implemented | `publicly_accessible = false`, `multi_az = false` |
| Encryption và network boundary | Implemented | `storage_encrypted = true`, database SG input |
| Backup và deletion lifecycle | Implemented | Backup windows, final snapshot và deletion protection inputs |
| RDS CloudWatch log groups | Implemented | `aws_cloudwatch_log_group.rds` và `enabled_cloudwatch_logs_exports` |
| Credential boundary | Implemented | Sensitive password input, không có password output/secret resource |
| Environment composition | Implemented | `environments/dev/main.tf` nối network, SG và database inputs |
| Output contract | Implemented | `modules/database/outputs.tf` và root re-exports |
| Terraform validation | Blocked | Provider plugin trong `environments/dev/.terraform` không khởi động được; `fmt` đã chạy |

## Điều kiện chấp nhận

- RDS dùng đúng `module.network.database_subnet_ids` và subnet group không chứa public subnets.
- `publicly_accessible` là `false`, `multi_az` là `false`, storage encryption được bật.
- Database security group chỉ cho application security group truy cập database port.
- Không có output nào trả về password hoặc secret value.
- CloudWatch log groups chỉ được tạo cho log types được chọn và có retention rõ ràng.
- `database_password` được cấp ngoài mã nguồn và backend state phải được bảo vệ như dữ liệu nhạy cảm.

## Rủi ro và quyết định còn mở

- RDS nhận password qua Terraform resource argument, vì vậy password có thể xuất hiện trong state dù biến là `sensitive`. Cần chọn backend state có encryption/access control trước khi triển khai.
- Engine log export phải phù hợp với engine/version đã chọn; Terraform validation không xác minh được availability theo từng AWS region.
- Việc để RDS tự quản lý master password bằng Secrets Manager hoặc đọc secret hiện có là cải tiến riêng, cần chốt schema secret và quyền IAM trước khi triển khai.
