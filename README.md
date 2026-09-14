# AWS three-tier infrastructure with Terraform

Repository mô tả kiến trúc AWS ba tầng cho frontend tĩnh và NodeJS API:

```text
User --HTTPS--> CloudFront --OAC--> private S3 (frontend build)
                       |
                       +-- /api/* + custom header --HTTPS origin--> internet-facing ALB
                                                     --HTTP--> EC2 API ASG (2 AZs)
                                                                  --DB port--> private RDS
```

CloudFront redirect viewer HTTP sang HTTPS. Giai đoạn hiện tại người dùng truy cập bằng hostname mặc định `https://<distribution>.cloudfront.net` và certificate mặc định của CloudFront; custom viewer domain là `Optional / Future improvement`. CloudFront → ALB có mục tiêu HTTPS độc lập với viewer domain, cần ALB origin domain và certificate regional khớp domain đó. S3 không public; bucket policy chỉ cho CloudFront OAC đọc. ALB chỉ forward `/api` và `/api/*` khi header bí mật khớp; ALB security group chỉ nhận listener port từ AWS CloudFront origin-facing managed prefix list. EC2 có public IPv4 để bootstrap/outbound qua Internet Gateway nhưng security group không mở NodeJS port cho Internet. Không tạo NAT Gateway. RDS là đúng một instance Single-AZ, private và `publicly_accessible = false`.

## Cấu trúc

Root module vẫn ở `environments/dev` và module dùng chung ở `modules/`. Repository ban đầu đã có cấu trúc này nhưng các module rỗng; giữ nguyên giúp tránh đổi module source và state addresses vô cớ. Không có state/resource cũ trong repository, cũng không có `AGENTS.md`, workflow, OPA/Rego policy hoặc state file cần migration.

| Module | Trách nhiệm |
|---|---|
| `network` | VPC, hai public subnet, hai private DB subnet, IGW, route tables/associations |
| `security-groups` | ALB-SG, EC2-SG, RDS-SG và các rule theo luồng ALB → EC2 → RDS |
| `frontend` | Private S3, public access block, OAC, bucket policy và CloudFront origins/behaviors |
| `certificates` | Certificate regional cho ALB origin HTTPS; CloudFront viewer certificate `us-east-1` là optional/future |
| `alb` | Internet-facing ALB, target group, `/health`, listener và custom-header rule |
| `compute` | IAM/SSM, Launch Template, user data, ASG 2+ instance và CPU scaling |
| `database` | DB subnet group và đúng một RDS Single-AZ |
| `monitoring` | CloudWatch log groups, native metric alarms và API log metric filter |

## Ánh xạ 32 thành phần

| # | Thành phần | Module/tài liệu |
|---:|---|---|
| 1 | User vào qua HTTPS | `frontend` / CloudFront |
| 2 | CloudFront distribution | `frontend` |
| 3 | Viewer HTTP redirect HTTPS | `frontend` |
| 4 | Private S3 frontend bucket | `frontend` |
| 5 | S3 OAC SigV4 | `frontend` |
| 6 | Behavior `/api/*` | `frontend` |
| 7 | Internet-facing ALB | `alb` |
| 8 | ALB HTTPS listener | `alb` + `certificates` |
| 9 | Custom origin-header authorization | `alb` |
| 10 | CloudFront managed prefix list ingress | `security-groups` |
| 11 | Single VPC | `network` |
| 12 | Hai Availability Zones | `network` |
| 13 | Internet Gateway | `network` |
| 14 | Hai public subnets | `network` |
| 15 | Public default route tới IGW | `network` |
| 16 | Hai private DB subnets | `network` |
| 17 | DB route table không có default route | `network` |
| 18 | API Auto Scaling Group | `compute` |
| 19 | Launch Template | `compute` |
| 20 | Public IPv4 nhưng không mở app trực tiếp | `compute` + `security-groups` |
| 21 | NodeJS API và `/health` | `compute` |
| 22 | IAM role/SSM instance profile | `compute` |
| 23 | IMDSv2 bắt buộc | `compute` |
| 24 | EBS gp3 mã hóa | `compute` |
| 25 | RDS DB subnet group | `database` |
| 26 | Đúng một RDS instance | `database` |
| 27 | RDS Single-AZ/private | `database` |
| 28 | ALB security group | `security-groups` |
| 29 | EC2 security group | `security-groups` |
| 30 | RDS security group | `security-groups` |
| 31 | ALB regional certificate; CloudFront viewer certificate chỉ ở custom-domain phase | `certificates` |
| 32 | Logs, metrics và alarms | `monitoring` |

## Khởi tạo và triển khai

Chi tiết backend, domain/certificate, artifact API và frontend build nằm trong [`docs/deployment.md`](docs/deployment.md) và [`docs/backend-bootstrap.md`](docs/backend-bootstrap.md).

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
# Cấp db_password và cloudfront_origin_header_value bằng môi trường/CI secret.
terraform init -backend=false
cd ../..
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
```

Nếu dùng remote state, tạo `backend.hcl` local theo tài liệu rồi chạy `terraform init -backend-config=backend.hcl`. Không chạy `apply` hoặc `destroy` trong quy trình kiểm tra local. `plan` cần AWS credentials, quyền đọc AMI/AZ/prefix list và các input secret; chưa có các điều kiện đó thì chỉ kết luận được `fmt/init/validate`.

## Secrets và artifact

Không commit password, origin-header value, credentials thật, state, plan hoặc `terraform.tfvars`. Sensitive variable chỉ ẩn khỏi một số output CLI; password và custom origin header vẫn có thể tồn tại trong Terraform state và Launch Template metadata. Dùng remote backend có mã hóa/access control, hoặc CI secret injection. API ZIP là artifact bên ngoài Terraform; nếu truyền `api_artifact_s3_bucket/key`, EC2 role chỉ được đọc object đó. Nếu chưa truyền artifact, user data tạo health-only fallback để target group có thể healthy; cần thay bằng application thật trước production.

## Chi phí

Ước tính theo Region, thời gian chạy và traffic bằng [AWS Pricing Calculator](https://calculator.aws/): chọn VPC/IGW (không có NAT Gateway), CloudFront, S3, ALB, EC2 theo ASG capacity/instance type, RDS Single-AZ/class/storage/backup, CloudWatch Logs/metrics/alarms và data transfer. `terraform` không tạo Pricing Calculator resource. NAT Gateway được cố ý loại bỏ vì kiến trúc dùng public IPv4 + IGW cho EC2 outbound; đây là trade-off cần đánh giá lại nếu yêu cầu bảo mật outbound thay đổi.
