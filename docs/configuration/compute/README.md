# Compute và API runtime configuration

## Mục tiêu

EC2 Auto Scaling Group chạy API trên hai public subnets. Runtime dự kiến là Docker:

```text
Dockerfile → Docker Hub image → EC2 docker pull → container :3000
```

ALB forward HTTP tới host port `3000`; container phải listen trên `0.0.0.0:3000`.

## Docker contract

- Image tag phải cố định, ví dụ `username/ecommerce-api:1.0.0`; không dùng `latest` cho
  release cần rollback.
- Image phải có manifest tương thích với EC2 Linux `amd64`.
- Image phải có production dependencies và health endpoint `/health`.
- Bootstrap cài Docker, pull image và chạy container với `-p 3000:3000`.
- Build/push Docker Hub không thuộc Terraform.
- Application logs từ stdout/stderr của container dùng Docker `awslogs` driver tới
  `/aws/<project>-<environment>/api`; log group đã được Terraform tạo trước khi EC2
  khởi động. Mỗi instance dùng stream `<project>-<environment>-api/<hostname>`.
- EC2 instance role chỉ cần `logs:CreateLogStream`, `logs:DescribeLogStreams` và
  `logs:PutLogEvents` trên hai log group; `awslogs-create-group=false` tránh cấp quyền
  tạo log group từ Docker.
- CloudWatch Agent chỉ thu `cloud-init-output.log` và memory/disk metrics, không thu lại
  Docker container log.
- Bootstrap hiện hỗ trợ public Docker Hub image. Private repository cần bổ sung cơ chế
  login an toàn trước khi dùng; không ghi credential vào user data, HCL hoặc `.tfvars`.

## Giữ nguyên

- ASG, rolling instance refresh, target group registration và CPU scaling.
- EC2 instance profile, SSM, IMDSv2 và encrypted gp3.
- `DATABASE_URL`, `SESSION_HMAC_SECRET`, `CORS_ORIGIN` và database pool settings được
  truyền vào container qua `/etc/nodejs-api.env`.
- CloudWatch metrics, system logs và application logs qua Docker `awslogs`.

## Checklist

| Hạng mục | Trạng thái |
|---|---|
| EC2 ASG + target group | Current |
| Docker bootstrap + Docker Hub pull | Implemented, chưa apply |
| Dockerfile/API image | Ngoài Terraform, cần image tồn tại trước bootstrap |
| Container stdout/stderr → CloudWatch Logs `awslogs` | Implemented, chưa apply |
| Health `/health` và port `3000` | Contract cần application đáp ứng |
| Database secret runtime lookup | Partial/current |

## Acceptance criteria cho Docker logs

- Application ghi log ra stdout/stderr; không phụ thuộc vào file log bên trong container.
- Log group API tồn tại trước `docker run` và không được Docker tự tạo.
- Mỗi EC2 instance có stream riêng để dễ truy vết khi ASG scale out.
- Khi container restart, Docker tiếp tục dùng cùng stream name của instance; log group vẫn
  được giữ theo `log_retention_days`.
- Việc `terraform apply` và kiểm tra log thực tế trên AWS vẫn chưa được thực hiện trong
  repository này.
