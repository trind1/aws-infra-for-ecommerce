# AWS infrastructure for e-commerce

Repository này chứa Terraform infrastructure cho môi trường `dev` của ứng dụng
e-commerce gồm frontend tĩnh, Node.js API và PostgreSQL trên AWS.

Terraform chỉ tạo hạ tầng và bootstrap EC2. Build/push Docker image, chạy Prisma
migration, provision admin và upload frontend là các bước triển khai sau `terraform apply`.

## Kiến trúc hiện tại

```text
Browser
├── https://<cloudfront-domain>/
│   └── CloudFront → S3 private + OAC → frontend static files
│
└── https://e-commerce-ndt.test/api/...
    └── ALB HTTPS :443
        └── EC2 Auto Scaling Group → Docker nodejs-api :3000
            └── RDS PostgreSQL :5432
```

Frontend và API dùng hai hostname khác nhau:

- CloudFront default domain phục vụ frontend.
- `e-commerce-ndt.test` là local/test API domain, cần cấu hình DNS thủ công trên máy test.
- API phải cho phép CORS từ CloudFront origin.
- `enable_cloudfront_api = false` trong `dev`, nên CloudFront không proxy `/api/*`.
- ALB HTTP rule và CloudFront API path cũ vẫn được giữ làm rollback path; direct API dùng
  ALB HTTPS rule trên port `443`.

`e-commerce-ndt.test` chưa được Terraform quản lý DNS. Trước khi ALB tồn tại cũng chưa
biết được DNS name AWS cấp; lấy giá trị đó từ Terraform output sau `apply`.

## Các thành phần

| Thành phần | Trách nhiệm |
|---|---|
| `network` | VPC, public subnets, private database subnets và route tables |
| `security-groups` | Luồng ALB → EC2 → RDS |
| `alb` | ALB, target group port `3000`, health check `/health`, HTTP và HTTPS test listener |
| `frontend` | S3 private, versioning, SSE-S3, OAC và CloudFront |
| `database` | RDS PostgreSQL private, backups và database logs |
| `compute` | IAM, SSM, Launch Template, Docker bootstrap, ASG và CPU scaling |
| `monitoring` | CloudWatch log groups, Docker/system logs, metrics và alarms |

## Repository layout

```text
.
├── environments/dev/              # Root Terraform composition
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── admin-provision.env.example
├── modules/                        # Terraform modules
├── scripts/
│   ├── generate-alb-self-signed-cert.sh
│   ├── run-db-migration.sh
│   └── provision-admin.sh
└── docs/deployment/dev-apply-runbook.md
```

## Yêu cầu trước khi triển khai

Máy deploy cần có:

- Terraform `>= 1.5.0`.
- AWS CLI và credentials đúng AWS account/region.
- Docker để build và push API image.
- Quyền IAM tạo VPC, ALB, EC2/ASG, RDS, S3, CloudFront, ACM import và CloudWatch.
- AWS region phù hợp với các Availability Zone trong `terraform.tfvars`.

App repository cần chuẩn bị:

- Docker image API cho `linux/amd64`.
- Image có tag cố định, không dùng `latest`.
- Image chứa Prisma migration files.
- Image có script `db:deploy` và `auth/provision-admin.js`.
- Frontend build dùng:

```ini
VITE_API_URL=https://e-commerce-ndt.test/api
```

## Secret và file local

Các file thật sau đây chỉ tồn tại local và không được commit:

- `environments/dev/terraform.tfvars`
- `environments/dev/admin-provision.env`
- `environments/dev/local-certs/alb.key.pem`
- Terraform state và plan files

Bảo vệ file input:

```bash
chmod 600 environments/dev/terraform.tfvars
chmod 600 environments/dev/admin-provision.env
```

Dev hiện dùng local Terraform state, không dùng remote S3 backend. Vì vậy không dùng
local state cho team hoặc production. State và `terraform.tfvars` có thể chứa secret và
phải được bảo vệ như dữ liệu nhạy cảm.

## Quy trình triển khai

Quy trình đầy đủ nằm tại [docs/deployment/dev-apply-runbook.md](docs/deployment/dev-apply-runbook.md).

Tóm tắt:

1. Build và push API Docker image.
2. Tạo certificate test và cấu hình client CIDR.
3. Điền `terraform.tfvars` và tạo custom CloudFront header secret.
4. Chạy `init`, `fmt`, `validate`, `plan` và review plan.
5. Apply đúng plan đã review.
6. Cấu hình DNS local cho `e-commerce-ndt.test`.
7. Chạy migration một lần qua SSM.
8. Provision admin một lần qua SSM.
9. Build/upload frontend và invalidate CloudFront.
10. Kiểm tra ALB, EC2, RDS, CORS, CloudWatch logs và alarms.

Các lệnh sau `apply` không được đặt trong `user_data`:

- `docker exec nodejs-api npm run db:deploy`
- `node apps/api/dist/auth/provision-admin.js`

Lý do là ASG có thể khởi động nhiều EC2; migration và admin provisioning chỉ chạy trên
một instance/runner duy nhất.

## Giới hạn dev

- EC2 nằm trong public subnets và dùng public IPv4 để bootstrap/pull image.
- RDS là Single-AZ mặc định.
- ALB HTTPS dev dùng certificate self-signed được import vào ACM.
- DNS API là local/manual, chưa có Route 53 resource.
- Terraform state là local.
- Chưa có WAF, CI/CD, Secrets Manager, remote backend hoặc production DR workflow.
- Docker logs đi trực tiếp tới CloudWatch bằng `awslogs` driver; CloudWatch Agent xử lý
  system log và metrics của EC2.

## Tài liệu liên quan

- [Dev apply runbook](docs/deployment/dev-apply-runbook.md)
- [Dev verification test plan](docs/deployment/dev-verification-test-plan.md)
- [Architecture](docs/architecture/README.md)
- [Components](docs/components/README.md)
- [Configuration](docs/configuration/README.md)
- [Cost estimation](docs/cost-estimation/README.md)
