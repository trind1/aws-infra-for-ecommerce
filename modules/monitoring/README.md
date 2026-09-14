# Monitoring module

Module tạo CloudWatch log groups, metric filter và alarms cho các thành phần vận hành của kiến trúc three-tier:

- API/system log groups cho EC2 CloudWatch Agent.
- ALB alarms cho ELB-side 5XX và unhealthy targets.
- ASG alarms cho CPU và số instance in-service.
- RDS alarms cho CPU và free storage.
- API error metric filter và alarm trên custom namespace.

RDS engine log groups thuộc module `database`. ALB access logging tới S3, SNS topic, dashboard và CloudWatch Agent installation không thuộc module này.

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 7
- Validated: 1
- Blocked: 1
- Not in scope: 0

## Hành vi và boundary

Module nhận các identity/suffix của ALB, target group, ASG và RDS từ composition layer. Module không tự tìm resource bằng data source và không tạo notification topic. `alarm_actions` chỉ là danh sách ARN được truyền vào; có thể để `[]` nếu chưa cấu hình kênh cảnh báo.

Common tags được áp dụng ở provider `default_tags`; module không có `tags` variable. Module chỉ thêm tags riêng cho log groups như `Name`, `Component` và `Tier`.

## Inputs

| Input | Bắt buộc | Ý nghĩa |
|---|---:|---|
| `project_name` | Có | Project identifier dùng trong tên resource |
| `environment` | Có | Environment identifier dùng trong tên resource |
| `alb_arn_suffix` | Có | ALB ARN suffix cho dimension `LoadBalancer` |
| `target_group_arn_suffix` | Có | Target group ARN suffix cho dimension `TargetGroup` |
| `autoscaling_group_name` | Có | ASG name cho dimension Auto Scaling/EC2 |
| `db_instance_identifier` | Có | RDS identifier cho dimension DB |
| `log_retention_days` | Không | Retention API/system log groups, mặc định `14` |
| `alarm_actions` | Không | ARN nhận alarm, mặc định `[]` |
| `alb_5xx_threshold` | Không | ALB 5XX threshold, mặc định `10` |
| `alb_unhealthy_host_threshold` | Không | Unhealthy target threshold, mặc định `1` |
| `asg_cpu_threshold` | Không | ASG CPU threshold, mặc định `80` |
| `asg_in_service_threshold` | Không | In-service instance threshold, mặc định `1` |
| `rds_cpu_threshold` | Không | RDS CPU threshold, mặc định `80` |
| `rds_free_storage_threshold_bytes` | Không | RDS free storage threshold, mặc định `5368709120` |
| `api_error_count_threshold` | Không | API errors threshold mỗi 5 phút, mặc định `10` |

## Resources

| Nhóm | Resources |
|---|---|
| Logs | `aws_cloudwatch_log_group.api`, `aws_cloudwatch_log_group.system` |
| ALB alarms | `aws_cloudwatch_metric_alarm.alb_5xx`, `aws_cloudwatch_metric_alarm.alb_unhealthy_hosts` |
| ASG alarms | `aws_cloudwatch_metric_alarm.asg_cpu`, `aws_cloudwatch_metric_alarm.asg_in_service` |
| RDS alarms | `aws_cloudwatch_metric_alarm.rds_cpu`, `aws_cloudwatch_metric_alarm.rds_free_storage` |
| API errors | `aws_cloudwatch_log_metric_filter.api_errors`, `aws_cloudwatch_metric_alarm.api_errors` |

Metric filter tạo custom metric không có dimension. Vì vậy alarm API cũng không gắn `LogGroupName` dimension; dimension đó sẽ không khớp metric được tạo bởi filter hiện tại.

## Outputs

| Output | Consumer / mục đích |
|---|---|
| `api_log_group_name` | CloudWatch Agent gửi application logs |
| `system_log_group_name` | CloudWatch Agent gửi bootstrap/system logs |
| `metric_namespace` | Compute/application gửi custom metrics |
| `alarm_arns` | Inventory và vận hành alarm |
| `alarm_names` | Tham chiếu tên alarm trong vận hành |

## Ví dụ composition

```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  environment  = var.environment

  alb_arn_suffix          = module.alb.load_balancer_arn_suffix
  target_group_arn_suffix = module.alb.target_group_arn_suffix
  autoscaling_group_name  = module.compute.autoscaling_group_name
  db_instance_identifier  = module.database.db_instance_identifier

  log_retention_days           = var.log_retention_days
  alarm_actions                = var.alarm_actions
  alb_5xx_threshold             = var.alb_5xx_threshold
  alb_unhealthy_host_threshold = var.alb_unhealthy_host_threshold
  asg_cpu_threshold            = var.asg_cpu_threshold
  asg_in_service_threshold     = var.asg_in_service_threshold
  rds_cpu_threshold            = var.rds_cpu_threshold
  rds_free_storage_threshold_bytes = var.rds_free_storage_threshold_bytes
  api_error_count_threshold    = var.api_error_count_threshold
}
```

Khi compute cần tên log groups, composition không được tạo dependency cycle bằng cách để monitoring vừa lấy output của compute cho alarms vừa buộc compute phụ thuộc vào alarm resources. Có thể dùng naming contract ổn định hoặc tách log foundation khỏi alarm composition trong change riêng.

## Implementation checklist

| # | Hạng mục | Trạng thái | Evidence code | Evidence validation | Consumer / ghi chú |
|---:|---|---|---|---|---|
| 1 | Boundary và non-goals | Implemented | `modules/monitoring/README.md:11` | Chưa xác minh | Không tạo SNS, dashboard, agent hoặc RDS log groups |
| 2 | Input contract không dùng `tags` variable | Implemented | `modules/monitoring/variables.tf:1` | Chưa xác minh | Common tags do provider `default_tags` quản lý |
| 3 | API/system CloudWatch log groups | Implemented | `modules/monitoring/main.tf:10` | Chưa xác minh | Output cho compute/CloudWatch Agent |
| 4 | ALB, ASG, RDS metric alarms | Implemented | `modules/monitoring/main.tf:34` | Chưa xác minh | Dimensions lấy từ upstream outputs |
| 5 | API metric filter và alarm | Implemented | `modules/monitoring/main.tf:149` | Chưa xác minh | Không dùng `LogGroupName` dimension sai |
| 6 | Output log groups, namespace và alarms | Implemented | `modules/monitoring/outputs.tf:1` | Chưa xác minh | Re-export ở environment |
| 7 | Environment wiring | Implemented | `environments/dev/main.tf:120` | Chưa xác minh | Chờ ALB/compute/database identities |
| 8 | HCL formatting | Validated | `modules/monitoring/main.tf:1`, `environments/dev/main.tf:120` | `terraform fmt -check modules/monitoring environments/dev/main.tf environments/dev/outputs.tf environments/dev/variables.tf` — exit 0 | Trong phạm vi module và wiring monitoring |
| 9 | Root composition validation | Blocked | `environments/dev/main.tf:72` | `terraform -chdir=environments/dev validate` — thiếu required arguments của `module.alb` | Cần hoàn thiện ALB wiring rồi chạy lại |
