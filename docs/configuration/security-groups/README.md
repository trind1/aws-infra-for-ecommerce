# Kế hoạch cấu hình: security-groups

## Mục tiêu

Thiết lập chuỗi allow-list tối thiểu cho CloudFront → ALB → application → RDS; không dùng CIDR Internet rộng cho application hoặc database.

## Dịch vụ và cấu hình

| Security group | Ingress mục tiêu | Egress mục tiêu |
|---|---|---|
| ALB | Managed prefix list origin-facing của CloudFront vào listener port. | Chỉ tới application security group trên app port. |
| Application | Chỉ từ ALB security group trên app port. | Tới database security group trên DB port; outbound cần thiết để bootstrap/CloudWatch qua Internet Gateway. |
| Database | Chỉ từ application security group trên DB port. | Chỉ response traffic theo nhu cầu của database engine. |

## Input cần quyết định

- VPC ID từ module network.
- CloudFront origin-facing managed prefix list ID theo AWS region.
- Listener port, application port và database port.
- Tags chung cho ba security groups do provider `default_tags` áp dụng.

## Output contract

- ALB security group ID cho module ALB.
- Application security group ID cho module compute.
- Database security group ID cho module database.

## Điều kiện chấp nhận

- Không có ingress `0.0.0.0/0` vào application hoặc database.
- ALB không cho phép người dùng bypass CloudFront.
- Mỗi rule dùng security-group reference khi nguồn là tier nội bộ; không hard-code IP instance.
