# AWS infrastructure for e-commerce

Terraform project triển khai một hệ thống e-commerce đơn giản trên AWS, gồm frontend tĩnh, Node.js API và PostgreSQL database.

> Hiện repository chỉ có composition cho môi trường `dev` tại [`environments/dev`](environments/dev). Đây là infrastructure baseline; chưa bao gồm pipeline build/deploy ứng dụng và chưa nên dùng trực tiếp cho production.

## Kiến trúc

```text
                         HTTPS
 User ─────────────────────────────► CloudFront
                                      │
                         ┌────────────┴────────────┐
                         │                         │
                    Frontend                    API /api/*
                         │                  HTTP + custom header
                         ▼                         ▼
                 S3 private + OAC              ALB HTTP :80
                                                     │
                                             HTTP nội bộ :3000
                                                     ▼
                                           EC2 Auto Scaling Group
                                                     │
                                             PostgreSQL :5432
                                                     ▼
                                                RDS private
```

### Các thành phần chính

- **CloudFront:** điểm truy cập HTTPS cho người dùng.
- **S3 private:** lưu frontend build; chỉ CloudFront đọc qua Origin Access Control (OAC).
- **ALB:** nhận API traffic từ CloudFront, kiểm tra custom header và forward tới EC2.
- **EC2 Auto Scaling Group:** chạy Node.js API trên hai Availability Zones.
- **RDS PostgreSQL:** database private, hiện cấu hình Single-AZ.
- **CloudWatch:** lưu logs, custom metrics và alarms.

### Network

- Một VPC với hai Availability Zones.
- Public subnets chứa ALB và EC2.
- Private database subnets chứa RDS.
- Không tạo NAT Gateway; EC2 dùng public IPv4 để bootstrap và outbound.
- Security group giới hạn luồng `CloudFront → ALB → EC2 → RDS`.

## Cấu trúc repository

```text
.
├── environments/dev/       # Root composition hiện tại
├── modules/                # Các Terraform module dùng chung
└── docs/                   # Kiến trúc, contract module và cost estimate
```

## Terraform modules

| Module | Trách nhiệm |
|---|---|
| [`network`](modules/network) | VPC, public/database subnets, route tables và Internet Gateway |
| [`security-groups`](modules/security-groups) | Security groups và rules giữa các tầng |
| [`certificates`](modules/certificates) | Module certificate reusable cho các environment HTTPS; không dùng trong dev hiện tại |
| [`alb`](modules/alb) | Internet-facing ALB, HTTP listener, target group và API rule |
| [`frontend`](modules/frontend) | S3 private, OAC, CloudFront distribution và API origin |
| [`database`](modules/database) | DB subnet group, RDS PostgreSQL và RDS logs |
| [`compute`](modules/compute) | IAM, Launch Template, EC2 ASG, bootstrap và CPU scaling |
| [`monitoring`](modules/monitoring) | CloudWatch log groups, metric filters và alarms |

Environment [`environments/dev/main.tf`](environments/dev/main.tf) chịu trách nhiệm nối các module với nhau.

## Kiểm tra cấu hình

Yêu cầu:

- Terraform `>= 1.5.0`
- AWS provider `~> 6.0`
- AWS credentials phù hợp nếu chạy `plan`

Chạy kiểm tra format và schema:

```bash
terraform version
terraform -chdir=environments/dev init -backend=false
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
```

Một số input bắt buộc phải được cấp từ biến môi trường, CI secret hoặc file `.tfvars` local, gồm:

- `cloudfront_alb_header_value`
- `database_password`

CloudFront origin-facing managed prefix list được Terraform tự động tra cứu theo AWS region hiện tại, nên không cần cung cấp `cloudfront_origin_prefix_list_id` thủ công.
AMI Amazon Linux 2023 x86_64 cho compute được Terraform lấy từ public SSM Parameter theo region hiện tại.

Không commit password, custom header value, credentials, state, plan hoặc file `terraform.tfvars`.

## State và triển khai

Hiện root module chưa khai báo remote backend. Vì vậy không nên dùng local state cho team hoặc production. Trước khi triển khai thật, cần bổ sung remote backend có encryption, locking, versioning và access control; sau đó tạo plan artifact để review trước khi apply.

Environment `dev` dùng trực tiếp DNS name AWS cấp cho ALB làm CloudFront HTTP origin; không cần domain hoặc ACM certificate. Việc upload frontend/API artifact hiện nằm ngoài Terraform composition này.

## Giới hạn hiện tại

- EC2 đang ở public subnets và có public IPv4 để bootstrap.
- RDS đang là Single-AZ; chưa có Multi-AZ/read replica/DR workflow.
- RDS password và custom origin header có thể xuất hiện trong Terraform state; backend phải được bảo vệ như dữ liệu nhạy cảm.
- CloudFront → ALB dùng HTTP cho dev/test; production cần environment riêng với HTTPS origin và certificate regional.
- Chưa có WAF, CI/CD workflow, policy-as-code hoặc security scanner trong repository.
- Frontend/API artifact upload và CloudFront invalidation chưa được quản lý ở đây.

## Tài liệu

- [Sơ đồ kiến trúc dùng thuyết trình](docs/architecture/README.md)
- [Kiến trúc tổng thể](docs/components/README.md)
- [Kế hoạch và contract cấu hình](docs/configuration/README.md)
- [Cost estimation](docs/cost-estimation/README.md)
- README riêng của từng module trong thư mục [`modules/`](modules)
