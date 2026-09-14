# Kế hoạch cấu hình: alb

Tài liệu này mô tả contract triển khai module ALB và evidence trong repository. Nó không khẳng định ALB hoặc HTTPS origin đã được tạo trên AWS.

## Mục tiêu

Đặt một Application Load Balancer public làm origin API cho CloudFront, cân bằng traffic tới EC2 Auto Scaling Group và chỉ forward request hợp lệ từ CloudFront. Kết nối CloudFront → ALB hiện tại bắt buộc là HTTPS. Custom viewer domain của CloudFront không điều khiển certificate hoặc protocol của ALB origin.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| Elastic Load Balancing v2 - ALB | Một ALB `application`, `internet-facing`, nằm trong đúng hai public subnets và gắn ALB security group. Bật `drop_invalid_header_fields` và cấu hình deletion protection/idle timeout từ environment. |
| Elastic Load Balancing v2 - target group | Target type `instance`, protocol HTTP, port là `application_port`; dùng health check HTTP tới `alb_health_check_path`, matcher `200-399`. |
| Elastic Load Balancing v2 - HTTPS listener | Listener ở `alb_listener_port` (environment mặc định `443`), dùng `alb_certificate_arn` là regional ACM certificate và `alb_ssl_policy`. Default action trả `403`. |
| Elastic Load Balancing v2 - listener rule | Priority cố định, match `/api` hoặc `/api/*` và custom header do CloudFront gửi; chỉ khi cả path và header đúng mới forward tới target group. |

ALB → EC2 vẫn là HTTP nội bộ theo thiết kế. HTTPS chỉ mô tả kết nối CloudFront → ALB; không trộn hai certificate hoặc hai kết nối này.

## Luồng truy cập

```text
Client
  │ HTTPS tới https://<distribution>.cloudfront.net
  │ certificate mặc định của CloudFront
  ▼
CloudFront
  │ HTTPS tới ALB origin hostname
  │ custom origin header
  ▼
ALB HTTPS listener :443
  │ path /api hoặc /api/* + header khớp
  ▼
Target group HTTP :application_port
  ▼
EC2 / Auto Scaling Group
```

Request trực tiếp không có header hợp lệ hoặc không khớp path API nhận `403` ở listener. Security group vẫn giới hạn ingress listener bằng CloudFront origin-facing managed prefix list.

## Input contract ở environment

| Input module ALB | Nguồn tại environment | Ghi chú |
|---|---|---|
| `vpc_id` | `module.network.vpc_id` | VPC của ALB. |
| `subnet_ids` | `module.network.public_subnet_ids` | Đúng hai public subnets. |
| `security_group_id` | `module.security_groups.alb_security_group_id` | SG chỉ nhận CloudFront prefix list. |
| `target_port` | `var.application_port` | Port HTTP của API trên EC2. |
| `health_check_path` | `var.alb_health_check_path` | Mặc định `/health`. |
| `listener_port` | `var.alb_listener_port` | Mặc định `443`, phải đồng nhất với ALB SG. |
| `certificate_arn` | `module.certificates.alb_certificate_arn` | Regional certificate; null cho tới khi sẵn sàng. |
| `ssl_policy` | `var.alb_ssl_policy` | TLS policy của listener. |
| `origin_custom_header_name/value` | `var.cloudfront_alb_header_name/value` | Tên/value phải đồng nhất với CloudFront; value là secret. |
| `enable_deletion_protection` | `var.alb_deletion_protection` | Mặc định tắt cho dev. |
| `idle_timeout` | `var.alb_idle_timeout_seconds` | Mặc định 60 giây. |

## Certificate và domain: điều kiện bắt buộc

Hai certificate phục vụ hai kết nối khác nhau:

1. **Client → CloudFront:** hiện dùng `https://<distribution>.cloudfront.net` và certificate mặc định do CloudFront cung cấp. Không cần domain riêng, Route 53 hosted zone, CloudFront alias hoặc ACM certificate `us-east-1` cho URL mặc định.
2. **CloudFront → ALB:** dùng certificate ACM regional của ALB. Certificate phải hợp lệ và khớp chính xác hostname CloudFront sử dụng làm ALB origin.

Repository hiện chưa chốt đầy đủ ALB origin hostname, DNS authoritative/management và phương án cấp/validate certificate cho hostname đó. Không được giả định certificate có thể cấp cho DNS mặc định `*.elb.amazonaws.com`; vì vậy trạng thái HTTPS origin là `BLOCKED` cho tới khi có quyết định và evidence kiểm chứng. Không chuyển protocol sang HTTP để bỏ qua blocker này.

Module ALB không tạo Route 53 hosted zone, alias record hoặc validation record. Route 53 chỉ có thể được dùng tùy chọn trong module `certificates` cho DNS validation; DNS provider bên ngoài cũng có thể đảm nhiệm validation.

## Output contract

| Output | Consumer | Mục đích |
|---|---|---|
| `alb_arn` | Environment/vận hành | Nhận diện ALB. |
| `alb_dns_name` | Frontend | Hostname origin của CloudFront; chỉ dùng khi certificate khớp hostname. |
| `alb_zone_id` | DNS tương lai | Canonical ELB zone ID cho alias; không phải hosted zone ID do module tạo. |
| `target_group_arn` | Compute | Đăng ký instances/ASG vào API target group. |
| `listener_arn`, `listener_port` | Vận hành | Kiểm tra listener và port HTTPS. |
| `load_balancer_arn_suffix`, `target_group_arn_suffix` | Monitoring | CloudWatch dimensions cho ALB và target group. |

## Checklist triển khai và evidence

| # | Hạng mục | Trạng thái | Evidence/kiểm tra |
|---:|---|---|---|
| 1 | ALB public trong hai public subnets, dùng ALB SG | Implemented | `modules/alb/main.tf:3`; wiring `environments/dev/main.tf:78` |
| 2 | Target group HTTP tới API và health check `/health` | Implemented | `modules/alb/main.tf:22` |
| 3 | Listener HTTPS, certificate regional bắt buộc, không có HTTP fallback | Implemented | `modules/alb/variables.tf:47`; `modules/alb/main.tf:50` |
| 4 | Rule API kiểm tra path và custom origin header | Implemented | `modules/alb/main.tf:76` |
| 5 | Output đủ cho frontend, compute và monitoring | Implemented | `modules/alb/outputs.tf:1`; `environments/dev/outputs.tf:64` |
| 6 | CloudFront → ALB HTTPS đã sẵn sàng trên AWS | Blocked | `docs/configuration/certificates/README.md:52`; origin hostname/DNS/certificate khớp chưa được chốt; chưa chạy apply |
| 7 | Route 53 hosted zone/alias cho ALB | Not in scope | Không có Route 53 resource trong module ALB |

## Kiểm tra đề xuất

```bash
terraform -chdir=environments/dev fmt -check -recursive
terraform -chdir=environments/dev validate
```

Các lệnh trên chỉ kiểm tra format và cấu trúc Terraform. Chúng không xác nhận DNS, ACM certificate đã `ISSUED`, CloudFront origin TLS handshake hoặc tài nguyên đã tồn tại. Không chạy `terraform apply` hoặc `terraform destroy` trong bước này.
