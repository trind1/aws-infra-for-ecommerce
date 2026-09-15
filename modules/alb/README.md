# Module: Application Load Balancer

Module này tạo lớp Application Load Balancer cho API trong kiến trúc three-tier. ALB là internet-facing và nằm trên hai public subnet; target group gửi traffic HTTP nội bộ tới EC2. Kết nối từ CloudFront tới ALB bắt buộc dùng HTTPS và certificate regional phải khớp hostname origin mà CloudFront sử dụng.

Custom viewer domain của CloudFront không thuộc module này. Ở giai đoạn hiện tại, người dùng truy cập CloudFront bằng hostname mặc định `*.cloudfront.net` và certificate mặc định do CloudFront cung cấp. Certificate đó không thay thế certificate regional của ALB.

## Sơ đồ và phạm vi

```text
CloudFront origin-facing prefix list
              │ TCP 443 + custom origin header
              ▼
       ALB security group
              │
              ▼
       ALB HTTPS listener
       default response: 403
              │ /api hoặc /api/*
              │ header X-Origin-Verify khớp
              ▼
     API target group (HTTP)
              │ application_port
              ▼
       EC2 / Auto Scaling Group
```

Module chỉ quản lý ALB, target group, listener và listener rule. Security groups thuộc module `security-groups`; việc đăng ký EC2 target thuộc module `compute`; certificate và DNS validation thuộc module `certificates`.

## Resources tạo ra

| Resource | Số lượng | Cấu hình chính |
|---|---:|---|
| `aws_lb.this` | 1 | `application`, `internet-facing`, trải trên đúng hai public subnets, bật loại bỏ invalid header. |
| `aws_lb_target_group.api` | 1 | `target_type = "instance"`, protocol HTTP, port nhận từ `target_port`. |
| `aws_lb_listener.api` | 1 | HTTPS, certificate regional bắt buộc, default action trả `403`. |
| `aws_lb_listener_rule.api_from_cloudfront` | 1 | Forward API khi path và custom origin header cùng khớp. |

## Luồng và hành vi

### ALB listener

- Listener dùng HTTPS ở `listener_port`, environment mặc định là `443`.
- `certificate_arn` là input bắt buộc và phải là certificate ACM regional đã hợp lệ.
- Certificate phải chứa đúng hostname CloudFront dùng làm ALB origin. Không coi DNS mặc định `*.elb.amazonaws.com` là tên có thể cấp certificate.
- Default action trả `403`, do đó request không khớp rule không được forward tới EC2.

### API listener rule

- Chỉ nhận `/api` và `/api/*`.
- Yêu cầu header do CloudFront thêm vào, mặc định tên là `X-Origin-Verify`.
- Giá trị header là input bắt buộc và nhạy cảm; không ghi giá trị thật vào repository.
- Security group giới hạn nguồn vào listener bằng CloudFront origin-facing managed prefix list. Custom header là lớp kiểm tra bổ sung ở listener, không thay thế security group.

### Target group và health check

- ALB gửi HTTP tới `target_port` của EC2; đây là kết nối nội bộ ALB → application, không phải kết nối CloudFront → ALB.
- Health check dùng HTTP tới `health_check_path`, matcher `200-399`, interval 30 giây, timeout 5 giây, ngưỡng healthy 2 và unhealthy 3.
- Compute module nhận `target_group_arn` để đăng ký instances/ASG vào target group.

## Inputs

| Name | Type | Required | Default | Mục đích |
|---|---|---:|---|---|
| `project_name` | `string` | Yes | - | Prefix tên resource. |
| `environment` | `string` | Yes | - | Tên môi trường. |
| `vpc_id` | `string` | Yes | - | VPC chứa ALB và target group. |
| `subnet_ids` | `list(string)` | Yes | - | Đúng hai public subnet cho ALB. |
| `security_group_id` | `string` | Yes | - | ALB security group từ module `security-groups`. |
| `target_port` | `number` | Yes | - | Port API trên EC2. |
| `health_check_path` | `string` | No | `/health` | Endpoint health check của API. |
| `listener_port` | `number` | Yes | - | HTTPS port của ALB; environment dùng `443`. |
| `certificate_arn` | `string` | Yes | - | Regional ACM certificate khớp origin hostname. |
| `ssl_policy` | `string` | No | `ELBSecurityPolicy-TLS13-1-2-2021-06` | TLS policy cho HTTPS listener. |
| `origin_custom_header_name` | `string` | No | `X-Origin-Verify` | Tên header CloudFront gửi tới ALB. |
| `origin_custom_header_value` | `string` | Yes | - | Giá trị bí mật dùng để authorize rule. |
| `enable_deletion_protection` | `bool` | No | `false` | Bảo vệ ALB khỏi xóa nhầm. |
| `idle_timeout` | `number` | No | `60` | ALB idle timeout tính bằng giây. |

Module không nhận `tags`. Provider của environment áp dụng `default_tags` chung; module bổ sung các tag định danh `Name`, `Component` và `Tier` cho từng resource.

## Outputs

| Output | Consumer | Ý nghĩa |
|---|---|---|
| `alb_arn` | Environment, vận hành | ARN của ALB. |
| `alb_dns_name` | Environment/vận hành | DNS name AWS cấp cho ALB; HTTPS origin hostname có thể được quản lý riêng để khớp certificate. |
| `alb_zone_id` | DNS tương lai | Canonical ELB zone ID cho alias nếu sau này cần; module không tạo Route 53 record. |
| `target_group_arn` | Compute | Target group để ASG đăng ký EC2. |
| `target_group_arn_suffix` | Monitoring | Dimension `TargetGroup` của CloudWatch. |
| `load_balancer_arn_suffix` | Monitoring | Dimension `LoadBalancer` của CloudWatch. |
| `listener_arn` | Environment/vận hành | ARN của HTTPS listener. |
| `listener_port` | Environment/vận hành | Port thực tế của listener. |

## Dependencies

```text
network ───────────────► vpc_id, public_subnet_ids
security-groups ───────► alb_security_group_id
certificates ──────────► alb_certificate_arn
                              │
                              ▼
                             alb
                              ├──► compute: target_group_arn
                              ├──► frontend: alb_dns_name
                              └──► monitoring: ARN suffixes
```

Certificate output có thể là `null` cho tới khi DNS validation hoàn tất hoặc có xác nhận certificate đã `ISSUED`. Khi đó composition phải dừng ở bước plan; module không chuyển listener sang HTTP để vượt qua điều kiện này.

## Checklist và evidence

| Hạng mục | Trạng thái | Evidence |
|---|---|---|
| Internet-facing ALB trên hai public subnets | Implemented | `main.tf:3`: resource `aws_lb.this` |
| Target group HTTP tới application port và health check | Implemented | `main.tf:22`: resource `aws_lb_target_group.api` |
| HTTPS listener với certificate regional bắt buộc | Implemented | `variables.tf:47`; `main.tf:50`: resource `aws_lb_listener.api` |
| Default response và custom header rule cho API | Implemented | `main.tf:76`: `aws_lb_listener_rule.api_from_cloudfront` |
| Contract cho frontend, compute và monitoring | Implemented | `outputs.tf:1`: ALB, target group và metric suffix outputs |
| HTTPS origin đã sẵn sàng trong AWS | Blocked | Cần origin hostname, DNS và certificate regional có thể kiểm chứng; chưa chạy apply |
| Hosted zone/alias Route 53 cho ALB | Not in scope | Module chỉ xuất `alb_zone_id`, không tạo DNS resource |

## Kiểm tra

Từ root environment có thể chạy:

```bash
terraform -chdir=environments/dev fmt -check -recursive
terraform -chdir=environments/dev validate
```

`validate` chỉ kiểm tra cấu trúc và schema Terraform; không chứng minh certificate đã `ISSUED`, DNS đã trỏ đúng hoặc ALB đã được triển khai. Không chạy `terraform apply` trong quá trình review module này.
