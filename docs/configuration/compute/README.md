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
- Application logs dùng Docker `awslogs` driver tới API log group; CloudWatch Agent chỉ
  thu cloud-init/system logs và metrics.
- Bootstrap hiện hỗ trợ public Docker Hub image. Private repository cần bổ sung cơ chế
  login an toàn trước khi dùng; không ghi credential vào user data, HCL hoặc `.tfvars`.

## Giữ nguyên

- ASG, rolling instance refresh, target group registration và CPU scaling.
- EC2 instance profile, SSM, IMDSv2 và encrypted gp3.
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` và Secrets Manager ARN.
- CloudWatch metrics, system logs và application logs qua Docker `awslogs`.

## Checklist

| Hạng mục | Trạng thái |
|---|---|
| EC2 ASG + target group | Current |
| Docker bootstrap + Docker Hub pull | Implemented, chưa apply |
| Dockerfile/API image | Ngoài Terraform, cần image tồn tại trước bootstrap |
| Container logs → CloudWatch `awslogs` | Implemented, chưa apply |
| Health `/health` và port `3000` | Contract cần application đáp ứng |
| Database secret runtime lookup | Partial/current |
