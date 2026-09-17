# Kế hoạch cấu hình environment `dev`

Đây là tài liệu thiết kế trước implementation cho kiến trúc:

```text
CloudFront HTTPS → S3 private + OAC
Direct client HTTPS → e-commerce-ndt.test → ALB :443
ALB → EC2/Docker :3000 → RDS PostgreSQL :5432
```

## Quyết định đã chốt

- Không tạo custom public domain cho CloudFront trong dev.
- Dùng hostname mặc định `*.cloudfront.net` cho frontend.
- Dùng `e-commerce-ndt.test` cho direct API local test.
- Dùng self-signed certificate generate local và import vào ACM regional cho ALB.
- Chỉ client CIDR đã khai báo được vào ALB HTTPS.
- CloudFront không còn là API entry point của dev sau implementation.
- Docker Hub image là phương án runtime dự kiến; image lifecycle nằm ngoài Terraform.

## Thứ tự module

1. `network`: tạo VPC và subnet topology.
2. `security-groups`: tạo ALB/app/database SG và HTTPS client allowlist.
3. `certificates-imported`: import certificate PEM local nếu bật test HTTPS.
4. `alb`: tạo ALB, target group `HTTP :3000`, listener `HTTPS :443` và API rule.
5. `frontend`: tạo S3 private/OAC/CloudFront chỉ cho static content.
6. `database`: tạo RDS PostgreSQL private.
7. `compute`: tạo EC2 ASG và bootstrap runtime.
8. `monitoring`: tạo logs, metrics và alarms.

## Contract cần chỉnh trước implementation

| Contract | Mục tiêu |
|---|---|
| Frontend API base URL | `https://e-commerce-ndt.test` |
| CloudFront API origin/behavior | `enable_cloudfront_api = false` trong `dev` |
| ALB HTTPS listener | Port `443`, imported ACM ARN |
| ALB direct API rule | Implemented: match `/api` và `/api/*`; không bắt secret header |
| Target group | HTTP tới host/container port `3000`; health check `/health` |
| Local DNS | Resolve `e-commerce-ndt.test` tới ALB |
| CORS | Allow đúng CloudFront origin, không dùng `*` nếu có credentials |
| Runtime | Docker image version cố định, không phụ thuộc `latest` |

## Inputs chính

- Network CIDRs và hai Availability Zones.
- `alb_https_client_cidr_blocks`, thường là public IP hiện tại với `/32`.
- Certificate/key path local và certificate version.
- Frontend bucket/CloudFront price class.
- RDS settings và database secret reference.
- Docker image URI có tag cố định từ Docker Hub.

## Security boundary

- Không mở application `3000` hoặc database `5432` ra Internet.
- Không commit private key, database password, custom header secret, `.tfvars`, state hoặc
  plan artifact.
- Self-signed certificate chỉ dùng dev/test; client phải trust certificate.
- Nếu dùng Docker Hub private repository, credential phải lấy từ Secrets Manager/SSM hoặc
  cơ chế CI an toàn, không ghi vào user data.
- EC2 hiện ở public subnet; đây là trade-off để bootstrap outbound không cần NAT Gateway.

## Checklist trước code

| Hạng mục | Trạng thái |
|---|---|
| Kiến trúc và endpoint | Planned/đã mô tả |
| Domain local và certificate workflow | Planned |
| ALB HTTPS direct API | Partial: resource test đã có, rule cần chỉnh |
| CloudFront chỉ static | Implemented bằng feature flag, chưa apply |
| Docker runtime | Implemented trong bootstrap, chưa apply |
| CORS và frontend API URL | Ngoài Terraform, cần application config |
| DNS local resolver | Ngoài Terraform, cần client setup |

## Validation sau implementation

```bash
terraform fmt -check -recursive
terraform -chdir=environments/dev init -backend=false
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan -out=dev.tfplan
```

Sau đó review riêng: security scan, target health, certificate trust, CORS, Docker logs,
API `/health`, API có database query và CloudFront static content. Chưa được xem là
deployed chỉ vì `validate` thành công.

## Rollback

Trước `apply`, rollback là bỏ các thay đổi code/docs sau khi review. Sau khi apply, trước
khi rollback phải tạo `plan -out` mới và kiểm tra resource sẽ bị thay đổi; không dùng
`destroy` để rollback toàn bộ environment.
