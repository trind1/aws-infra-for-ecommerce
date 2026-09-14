# Kế hoạch cấu hình: monitoring

> Tài liệu này mô tả thiết kế và implementation contract; không xác nhận hạ tầng đã được `apply`.

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 7
- Validated: 1
- Blocked: 1
- Not in scope: 0

## Mục tiêu và boundary

Tập trung log và alarm cho application, ALB, Auto Scaling Group và RDS. Module sở hữu CloudWatch log groups cho API/system log, application log metric filter và các metric alarms vận hành.

Module không tạo SNS topic, dashboard, CloudWatch Agent trên EC2, RDS engine log groups hoặc ALB access logging tới S3. Notification action chỉ nhận ARN từ environment; module không suy đoán topic/account.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| CloudWatch Log Groups | Hai log groups riêng cho API và system log, retention cấu hình được và có tên ổn định theo project/environment. |
| CloudWatch Logs metric filter | Đếm log entry chứa `ERROR`, `Error` hoặc `error` trong API log group. Metric không gắn dimension tùy chỉnh. |
| CloudWatch Alarm cho ALB 5XX | `AWS/ApplicationELB` với dimension `LoadBalancer = alb_arn_suffix`. |
| CloudWatch Alarm cho ALB unhealthy hosts | `AWS/ApplicationELB` với dimension `LoadBalancer` và `TargetGroup`. |
| CloudWatch Alarms cho ASG | CPU từ `AWS/EC2` và in-service instances từ `AWS/AutoScaling`, dimension theo ASG name. |
| CloudWatch Alarms cho RDS | CPU và free storage từ `AWS/RDS`, dimension theo DB instance identifier. |
| CloudWatch Alarm cho API errors | Alarm trên custom metric namespace của project, không thêm `LogGroupName` dimension sai với metric filter. |

## Dependency và metric dimensions

| Nguồn | Input monitoring | Cách lấy |
|---|---|---|
| ALB | `alb_arn_suffix` | `module.alb.load_balancer_arn_suffix` |
| API target group | `target_group_arn_suffix` | `module.alb.target_group_arn_suffix` |
| API Auto Scaling Group | `autoscaling_group_name` | `module.compute.autoscaling_group_name` |
| RDS | `db_instance_identifier` | `module.database.db_instance_identifier` |
| Environment | retention, thresholds, alarm actions | `var.*` của environment |

Monitoring chỉ tham chiếu identity của upstream resources cho alarms. Không dùng alarm resource làm dependency để compute lấy tên log group; khi nối compute, composition phải giữ dependency graph một chiều hoặc dùng naming contract ổn định.

## Input contract

| Input | Bắt buộc | Ý nghĩa |
|---|---:|---|
| `project_name` | Có | Project identifier dùng trong tên resource |
| `environment` | Có | Environment identifier dùng trong tên resource |
| `alb_arn_suffix` | Có | ARN suffix của ALB cho CloudWatch dimension |
| `target_group_arn_suffix` | Có | ARN suffix của target group cho CloudWatch dimension |
| `autoscaling_group_name` | Có | Tên ASG API cho CloudWatch dimension |
| `db_instance_identifier` | Có | RDS identifier cho CloudWatch dimension |
| `log_retention_days` | Không | Retention của API/system logs, mặc định `14` |
| `alarm_actions` | Không | ARN đích nhận alarm, mặc định `[]` |
| `alb_5xx_threshold` | Không | Ngưỡng ALB ELB-side 5XX trong 5 phút, mặc định `10` |
| `alb_unhealthy_host_threshold` | Không | Ngưỡng unhealthy target, mặc định `1` |
| `asg_cpu_threshold` | Không | Ngưỡng CPU ASG, mặc định `80` |
| `asg_in_service_threshold` | Không | Số instance in-service tối thiểu, mặc định `1` |
| `rds_cpu_threshold` | Không | Ngưỡng CPU RDS, mặc định `80` |
| `rds_free_storage_threshold_bytes` | Không | Ngưỡng free storage RDS, mặc định `5368709120` |
| `api_error_count_threshold` | Không | Ngưỡng application errors trong 5 phút, mặc định `10` |

## Alarm policy

| Alarm | Metric / period | Evaluation và missing data |
|---|---|---|
| ALB 5XX | `HTTPCode_ELB_5XX_Count` / 300 giây | 1 kỳ; `notBreaching` |
| ALB unhealthy | `UnHealthyHostCount` / 60 giây | 3 kỳ; `breaching` |
| ASG CPU | `CPUUtilization` / 300 giây | 2 kỳ; `notBreaching` |
| ASG in-service | `GroupInServiceInstances` / 60 giây | 3 kỳ; `breaching` |
| RDS CPU | `CPUUtilization` / 300 giây | 2 kỳ; `notBreaching` |
| RDS free storage | `FreeStorageSpace` / 300 giây | 1 kỳ; `notBreaching` |
| API errors | `ApplicationErrors` / 300 giây | 1 kỳ; `notBreaching` |

## Output contract

- `api_log_group_name` và `system_log_group_name` cho CloudWatch Agent/compute.
- `metric_namespace` cho custom application metrics.
- `alarm_arns` và `alarm_names` theo key ổn định cho vận hành, inventory và notification integration.

## Security và vận hành

- Log retention hữu hạn; không để log vô hạn ngoài chủ đích.
- Không đưa secret, database password hoặc token vào log pattern, alarm description, variable default hay output.
- Alarm actions là ARN tham chiếu, không phải credential; không hard-code account/topic.
- Metric dimension phải khớp metric thực tế; custom API metric không có dimension nếu metric filter không khai báo dimension.

## Điều kiện chấp nhận

- Compute có thể nhận tên log group mà không phụ thuộc vào alarm resources.
- ALB, ASG, RDS alarms dùng đúng namespace, metric và dimensions.
- Alarm API sử dụng custom metric do filter tạo ra và không có dimension thừa.
- Retention và thresholds đi từ environment, không hard-code ở resource.

## Implementation checklist

| # | Hạng mục | Trạng thái | Evidence code | Evidence validation | Consumer / ghi chú |
|---:|---|---|---|---|---|
| 1 | Boundary và non-goals | Implemented | `modules/monitoring/README.md:11` | Đối chiếu boundary — Pass | Không tạo SNS, dashboard, agent hoặc RDS log groups |
| 2 | Input contract không dùng `tags` variable | Implemented | `modules/monitoring/variables.tf:1` | `terraform fmt -check modules/monitoring environments/dev/main.tf environments/dev/outputs.tf environments/dev/variables.tf` — exit 0 | Common tags do provider `default_tags` quản lý |
| 3 | API/system CloudWatch log groups | Implemented | `modules/monitoring/main.tf:10` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments của `module.alb` | Output cho compute/CloudWatch Agent |
| 4 | ALB, ASG, RDS metric alarms | Implemented | `modules/monitoring/main.tf:34` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments của `module.alb` | Dimensions lấy từ upstream outputs |
| 5 | API metric filter và alarm | Implemented | `modules/monitoring/main.tf:149` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments của `module.alb` | Không dùng `LogGroupName` dimension sai |
| 6 | Output log groups, namespace và alarms | Implemented | `modules/monitoring/outputs.tf:1` | `terraform fmt -check modules/monitoring environments/dev/main.tf environments/dev/outputs.tf environments/dev/variables.tf` — exit 0 | Re-export ở environment |
| 7 | Environment wiring | Implemented | `environments/dev/main.tf:120` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments của `module.alb` | Đã nối ALB/compute/database outputs |
| 8 | HCL formatting | Validated | `modules/monitoring/main.tf:1`, `environments/dev/main.tf:120` | `terraform fmt -check modules/monitoring environments/dev/main.tf environments/dev/outputs.tf environments/dev/variables.tf` — exit 0 | Không chạy apply/plan trong scope này |
| 9 | Root composition validation | Blocked | `environments/dev/main.tf:72` | `terraform -chdir=environments/dev validate` — thiếu required arguments của `module.alb` | Cần hoàn thiện ALB wiring rồi chạy lại |
