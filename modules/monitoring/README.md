# Monitoring module

Tạo log groups cho application/bootstrap; metric alarms cho ALB (5xx, unhealthy targets), ASG/EC2 (CPU, in-service count), RDS (CPU, free storage) và NodeJS API (log metric filter cho error). RDS engine log groups thuộc module `database` để được tạo trước instance. CloudWatch Agent trên EC2 được cấu hình thống nhất từ các output log group/namespace này.

ALB không đẩy access log trực tiếp vào CloudWatch Logs; module dùng các metric native của `AWS/ApplicationELB`. Nếu cần access logs chi tiết, bật logging tới S3 trong một change riêng và tính chi phí lưu trữ/đọc dữ liệu.

| Input chính | Output chính |
|---|---|
| resource suffixes và thresholds | `api_log_group_name`, `system_log_group_name` |
| retention, alarm actions | `metric_namespace` |
