# Kế hoạch cấu hình: database

## Mục tiêu

Cung cấp một RDS Single-AZ private cho application, đặt trong database subnets và chỉ chấp nhận kết nối từ application tier.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| RDS DB subnet group | Gồm đúng hai database subnet IDs từ hai AZ. |
| Amazon RDS instance | Đúng một DB instance Single-AZ; không public; dùng database security group. |
| CloudWatch Logs | Tạo log groups cho các engine log exports đã chọn; retention được truyền từ environment. |
| Backup and recovery | Chốt backup retention, maintenance window, final snapshot và deletion protection theo mức độ quan trọng của môi trường. |
| Credentials | Username/password hoặc secret ARN được cấp từ secret store; không hard-code trong mã hay output. |

## Input cần quyết định

- Database subnets và database security group ID.
- Engine, version, instance class, allocated/max storage, database name và DB port.
- Backup/maintenance policy, immediate apply, final snapshot và deletion protection.
- Loại engine logs cần export, log retention và tags.
- Tham chiếu secret cho credentials.

## Output contract

- RDS identifier, ARN, endpoint/address và port cho compute/monitoring.
- DB subnet group name cho audit mạng.
- Danh sách RDS log-group names cho observability.

## Điều kiện chấp nhận

- `publicly_accessible` phải tắt; subnet group chỉ dùng database subnets.
- Chỉ application security group có ingress tới DB port.
- Single-AZ được ghi rõ là lựa chọn phạm vi hiện tại, không diễn đạt như cấu hình HA Multi-AZ.
