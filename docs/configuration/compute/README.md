# Kế hoạch cấu hình: compute

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 8
- Validated: 0
- Blocked: 1
- Not in scope: 2

## Mục tiêu

Chạy API trên EC2 Auto Scaling Group trong public subnets, nhận traffic từ ALB, kết nối private tới RDS và gửi log/metrics về CloudWatch. Module compute chỉ sở hữu runtime của API; network, ALB, database và monitoring foundation do các module khác cung cấp.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| IAM role/instance profile | Một role cho EC2, trust policy cho `ec2.amazonaws.com`, SSM managed policy và inline policies tối thiểu cho logs/metrics, artifact tùy chọn và database secret tùy chọn. |
| EC2 Launch Template | AMI bắt buộc từ environment, instance type, application SG, public IPv4, encrypted gp3 root volume, IMDSv2 bắt buộc và detailed monitoring tùy chọn. |
| User data bootstrap | Cài NodeJS/npm/unzip/AWS CLI/CloudWatch Agent, tải artifact tùy chọn, tạo systemd service và cấu hình API log/DB metadata. Không đưa database password vào user data. |
| Auto Scaling Group | Một ASG chạy trên đúng hai public subnet IDs, gắn vào ALB target group, health check type `ELB`, rolling instance refresh và min/desired/max capacity từ environment. |
| Auto Scaling policy | Một target-tracking policy theo `ASGAverageCPUUtilization`. |

Nếu không truyền artifact bucket/key, bootstrap dùng health-only NodeJS fallback để target có thể trả lời `/health`; đây không phải application production artifact.

## Phân cấp cấu hình

```text
network.public_subnet_ids
  └── compute.aws_autoscaling_group.api

security-groups.application_security_group_id
  └── compute.aws_launch_template.api

alb.target_group_arn
  └── compute.aws_autoscaling_group.api

monitoring.{api_log_group_name,system_log_group_name,metric_namespace}
  └── compute bootstrap và IAM policy

composition.compute_asg_name
  └── monitoring ASG alarms

database.{db_address,db_port}
  └── compute bootstrap connection metadata
```

## Input contract

| Nhóm | Input | Nguồn/ghi chú |
|---|---|---|
| Identity | `project_name`, `environment` | Environment, dùng cho tên ổn định. |
| EC2 | `ami_id`, `instance_type`, `root_volume_size`, `detailed_monitoring` | Composition lấy AMI Amazon Linux 2023 x86_64 từ public SSM Parameter theo region. |
| Network/traffic | `subnet_ids`, `security_group_id`, `target_group_arn`, `app_port` | Lần lượt từ network, security-groups, ALB và application port. |
| Scaling | `min_size`, `desired_capacity`, `max_size`, `cpu_target_value`, `health_check_grace_period` | Environment quyết định capacity và scaling behavior. |
| Artifact/bootstrap | `api_artifact_s3_bucket`, `api_artifact_s3_key`, `api_start_command`, `api_log_file` | Bucket/key đồng thời bật quyền `s3:GetObject` đúng object. |
| Observability | `api_log_group_name`, `system_log_group_name`, `metrics_namespace` | Từ monitoring log foundation; compute phụ thuộc log outputs, không tạo dependency cycle. |
| Database runtime | `database_host`, `database_port`, `database_name`, `database_username`, `database_credentials_secret_arn` | Host/port từ database; secret ARN chỉ là reference runtime. |

## Output contract

| Output | Consumer | Ý nghĩa |
|---|---|---|
| `autoscaling_group_name` | `monitoring` | Dimension cho EC2/Auto Scaling alarms. |
| `autoscaling_group_arn` | Environment/operations | ARN để audit và vận hành ASG. |
| `launch_template_id` | Environment/operations | Identity của Launch Template. |
| `instance_role_arn` | Environment/operations/audit | ARN của EC2 runtime role. |
| `instance_profile_name` | Environment/operations/audit | Instance profile gắn với Launch Template. |

Không export user data, password, secret value hoặc toàn bộ IAM policy object.

## Boundary bảo mật

- Application SG chỉ nhận application port từ ALB SG; module không mở ingress và không tạo SSH key path.
- EC2 có public IPv4 theo kiến trúc hiện tại để bootstrap qua Internet Gateway; database vẫn private.
- IMDSv2 (`http_tokens = "required"`) và encrypted gp3 EBS là mặc định bắt buộc.
- SSM dùng `AmazonSSMManagedInstanceCore` để quản trị không cần SSH.
- CloudWatch Logs chỉ được ghi vào hai log groups được cấp; `PutMetricData` bị giới hạn bởi metric namespace.
- Artifact policy chỉ cấp `s3:GetObject` cho đúng object khi cả bucket và key được cấu hình.
- Database secret policy chỉ tạo khi có ARN; quyền giới hạn vào ARN đó.

## Checklist triển khai

| Hạng mục | Trạng thái | Evidence code | Evidence validation |
|---|---|---|---|
| IAM role/profile và trust boundary | Implemented | `modules/compute/main.tf:74`, `modules/compute/main.tf:159` | `fmt -check` — Pass; schema validate — Blocked |
| SSM, logs, metrics và optional secret/artifact permissions | Implemented | `modules/compute/main.tf:86`, `modules/compute/main.tf:92`, `modules/compute/main.tf:132`, `modules/compute/main.tf:151` | `fmt -check` — Pass; schema validate — Blocked |
| Launch Template, IMDSv2 và encrypted EBS | Implemented | `modules/compute/main.tf:171`, `modules/compute/main.tf:205`, `modules/compute/main.tf:213` | `fmt -check` — Pass; schema validate — Blocked |
| Bootstrap systemd/CloudWatch Agent | Implemented | `modules/compute/user_data.sh.tftpl:1` | Template inspection — Chưa xác minh trên EC2 |
| ASG public subnets + ALB target group | Implemented | `modules/compute/main.tf:249`, `environments/dev/main.tf:161` | `fmt -check` — Pass; schema validate — Blocked |
| CPU target tracking và rolling refresh | Implemented | `modules/compute/main.tf:259`, `modules/compute/main.tf:295` | `fmt -check` — Pass; schema validate — Blocked |
| Environment wiring giữa network/SG/ALB/database/monitoring | Implemented | `environments/dev/main.tf:161`, `environments/dev/main.tf:200` | Composition validate — Blocked bởi AWS provider plugin |
| Output contract và monitoring consumer | Implemented | `modules/compute/outputs.tf:1`, `environments/dev/outputs.tf:114` | `fmt -check` — Pass; schema validate — Blocked |
| Formatting, validation và security scan | Blocked | `modules/compute`, `environments/dev` | `terraform fmt -check` — exit 0; `terraform validate` — provider handshake failure; scanners chưa cài |
| SSH access path | Not in scope | Không tạo key pair/SSH ingress | Theo thiết kế SSM |
| Production artifact build/release | Not in scope | Module chỉ tải artifact đã có | Cần pipeline riêng |

## Điều kiện chấp nhận

- `ami_id` phải được resolve từ public SSM Parameter trước plan; không để Launch Template triển khai với `null` image ID.
- ASG nhận đúng public subnet IDs, target group ARN và application port từ composition layer.
- EC2 không có SSH ingress trực tiếp, bắt buộc IMDSv2 và root EBS encrypted.
- User data không chứa database password; chỉ chứa endpoint metadata, username và secret ARN reference.
- IAM policy không cấp quyền đọc toàn bộ S3 bucket hoặc toàn bộ Secrets Manager nếu không có input tương ứng.
- Monitoring nhận `autoscaling_group_name` từ naming contract ổn định của composition; compute nhận log group outputs từ monitoring nên log foundation được tạo trước bootstrap.
- Fallback health-only chỉ là bootstrap safety net; production phải cung cấp artifact và start command đã kiểm chứng.

## Rủi ro và quyết định còn mở

- Public subnet + public IPv4 giúp bootstrap không cần NAT Gateway nhưng tăng attack surface; SG không có ingress public là điều kiện bắt buộc.
- `ignore_changes = [desired_capacity]` để autoscaling tự điều chỉnh capacity; thay đổi desired từ Terraform cần xử lý theo policy vận hành.
- `instance_refresh` có thể tạo thêm instance tạm thời trong rolling update, cần capacity/quota phù hợp.
- `database_credentials_secret_arn` mới chỉ cấp quyền và đưa ARN vào runtime env; application phải biết schema secret và tự đọc secret.
- AMI, NodeJS package và CloudWatch Agent availability theo region/runtime cần được kiểm tra bằng integration test hoặc golden AMI pipeline.
- AMI phải có SSM Agent đang chạy hoặc có cơ chế cài/khởi động SSM Agent; module chỉ cấp IAM permission, không tự cài agent.
