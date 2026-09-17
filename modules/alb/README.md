# Module: Application Load Balancer

Module này tạo lớp Application Load Balancer cho API trong kiến trúc three-tier. ALB là internet-facing và nằm trên hai public subnet; target group gửi traffic HTTP tới EC2. Trong environment `dev`, CloudFront kết nối tới ALB qua HTTP bằng DNS name AWS cấp; production cần composition riêng nếu muốn bật HTTPS origin.

Custom viewer domain và certificate không thuộc module này. Ở giai đoạn hiện tại, người dùng truy cập CloudFront bằng hostname mặc định `*.cloudfront.net` và certificate mặc định do CloudFront cung cấp.

## Sơ đồ và phạm vi

```text
CloudFront origin-facing prefix list
              │ TCP 80 + custom origin header
              ▼
       ALB security group
              │
              ▼
       ALB HTTP listener
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
| `aws_lb_listener.api` | 1 | HTTP, default action trả `403`. |
| `aws_lb_listener_rule.api_from_cloudfront` | 1 | Forward API khi path và custom origin header cùng khớp. |

## Luồng và hành vi

### ALB listener

- Listener dùng HTTP ở `listener_port`, environment `dev` mặc định là `80`.
- Origin HTTP là lựa chọn riêng cho dev/test; không dùng contract này cho production nếu cần mã hóa CloudFront → ALB.
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
| `listener_port` | `number` | Yes | - | HTTP port của ALB; environment `dev` dùng `80`. |
| `origin_custom_header_name` | `string` | No | `X-Origin-Verify` | Tên header CloudFront gửi tới ALB. |
| `origin_custom_header_value` | `string` | Yes | - | Giá trị bí mật dùng để authorize rule. |
| `enable_deletion_protection` | `bool` | No | `false` | Bảo vệ ALB khỏi xóa nhầm. |
| `idle_timeout` | `number` | No | `60` | ALB idle timeout tính bằng giây. |

Module không nhận `tags`. Provider của environment áp dụng `default_tags` chung; module bổ sung các tag định danh `Name`, `Component` và `Tier` cho từng resource.

## Outputs

| Output | Consumer | Ý nghĩa |
|---|---|---|
| `alb_arn` | Environment, vận hành | ARN của ALB. |
| `alb_dns_name` | Environment/vận hành | DNS name AWS cấp cho ALB và được dùng trực tiếp làm HTTP origin ở `dev`. |
| `alb_zone_id` | DNS tương lai | Canonical ELB zone ID cho alias nếu sau này cần; module không tạo Route 53 record. |
| `target_group_arn` | Compute | Target group để ASG đăng ký EC2. |
| `target_group_arn_suffix` | Monitoring | Dimension `TargetGroup` của CloudWatch. |
| `load_balancer_arn_suffix` | Monitoring | Dimension `LoadBalancer` của CloudWatch. |
| `listener_arn` | Environment/vận hành | ARN của HTTP listener. |
| `listener_port` | Environment/vận hành | Port thực tế của listener. |

## Dependencies

```text
network ───────────────► vpc_id, public_subnet_ids
security-groups ───────► alb_security_group_id
alb
  ├──► compute: target_group_arn
  ├──► frontend: alb_dns_name
  └──► monitoring: ARN suffixes
```

Trong `dev`, không có certificate hoặc DNS origin riêng; frontend dùng trực tiếp `alb_dns_name` và HTTP protocol.

## Checklist và evidence

| Hạng mục | Trạng thái | Evidence |
|---|---|---|
| Internet-facing ALB trên hai public subnets | Implemented | `main.tf:3`: resource `aws_lb.this` |
| Target group HTTP tới application port và health check | Implemented | `main.tf:22`: resource `aws_lb_target_group.api` |
| HTTP listener cho dev/test | Implemented | `variables.tf:43`; `main.tf:50`: resource `aws_lb_listener.api` |
| Default response và custom header rule cho API | Implemented | `main.tf:76`: `aws_lb_listener_rule.api_from_cloudfront` |
| Contract cho frontend, compute và monitoring | Implemented | `outputs.tf:1`: ALB, target group và metric suffix outputs |
| HTTP origin dùng ALB DNS name | Implemented | `modules/alb/outputs.tf:6`; composition truyền output sang frontend |
| HTTPS origin production | Not in scope | Cần certificate regional, hostname và protocol riêng |
| Hosted zone/alias Route 53 cho ALB | Not in scope | Dev dùng DNS name AWS cấp, không tạo DNS resource |

## Kiểm tra

Từ root environment có thể chạy:

```bash
terraform -chdir=environments/dev fmt -check -recursive
terraform -chdir=environments/dev validate
```

`validate` chỉ kiểm tra cấu trúc và schema Terraform; không chứng minh ALB, CloudFront hoặc target health đã được triển khai. Không chạy `terraform apply` trong quá trình review module này.
