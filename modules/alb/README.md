# ALB module

Module tạo internet-facing Application Load Balancer cho API, target group instance và
listener/rule. Trong kiến trúc mục tiêu, client đi trực tiếp tới HTTPS `443`; ALB forward
HTTP nội bộ tới application port `3000`.

## Resources

| Resource | Vai trò |
|---|---|
| `aws_lb.this` | Internet-facing ALB trên public subnets |
| `aws_lb_target_group.api` | Instance targets, HTTP tới `target_port` |
| `aws_lb_listener.api` | Listener HTTP legacy/CloudFront, default `403` |
| `aws_lb_listener.api_https_test` | Optional HTTPS `443` với imported ACM certificate |
| `aws_lb_listener_rule.*` | Routing `/api` và `/api/*` tới target group |

## Inputs chính

- `vpc_id`, `subnet_ids`, `security_group_id`
- `target_port`, `health_check_path`, `listener_port`
- `enable_https_listener`, `https_certificate_arn`
- `origin_custom_header_name`, `origin_custom_header_value` cho luồng CloudFront legacy
- `enable_deletion_protection`, `idle_timeout`

## Kiến trúc mục tiêu

```text
Allowed client → HTTPS :443 → ALB → HTTP :3000 → EC2/Docker
```

HTTPS direct API rule chỉ match path `/api` và `/api/*`; không bắt `X-Origin-Verify`.
HTTP CloudFront legacy rule vẫn giữ header condition để hỗ trợ rollback.

## Outputs

- `alb_arn`
- `alb_dns_name`
- `alb_zone_id`
- `target_group_arn`
- `target_group_arn_suffix`
- `https_listener_arn` khi listener được bật

## Trạng thái

| Hạng mục | Trạng thái |
|---|---|
| ALB, target group và HTTP listener | Current |
| Optional HTTPS listener `443` | Implemented, chưa apply |
| Imported ACM certificate wiring | Implemented, chưa apply |
| Direct rule không phụ thuộc secret header | Implemented, chưa apply |
| DNS Route 53 | Not in scope |

## Validation

```bash
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan -out=dev.tfplan
```
