# Dev deployment runbook

Runbook này mô tả toàn bộ quy trình triển khai `environments/dev`: chuẩn bị artifact,
kiểm tra Terraform, apply hạ tầng, chạy migration/provision admin và verification.

Không đặt password, session secret, admin secret, private key hoặc Terraform state thật
trong tài liệu này. Các lệnh được chạy từ root của infrastructure repository, trừ khi
ghi rõ là chạy từ app repository.

## Kiến trúc được triển khai

```text
Browser
├── https://<cloudfront-domain>/
│   └── CloudFront → S3 private + OAC → frontend
│
└── https://e-commerce-ndt.test/api/...
    └── ALB HTTPS :443
        └── EC2 Auto Scaling Group → Docker nodejs-api :3000
            └── RDS PostgreSQL :5432
```

Trong `dev`:

- CloudFront chỉ phục vụ frontend.
- `enable_cloudfront_api = false`; CloudFront không proxy `/api/*`.
- API dùng hostname riêng `e-commerce-ndt.test` và ALB HTTPS.
- DNS cho `e-commerce-ndt.test` phải cấu hình thủ công.
- ALB HTTP rule và CloudFront API path cũ vẫn được giữ cho rollback; direct HTTPS rule
  dùng path `/api` và `/api/*`.
- EC2 chạy Docker image bằng `user_data`; migration và admin provisioning chạy sau đó
  trên một instance duy nhất qua SSM.

## 1. Chuẩn bị công cụ và quyền AWS

Kiểm tra trên máy deploy:

```bash
terraform version
aws --version
docker --version
aws sts get-caller-identity
```

AWS credentials phải có quyền tạo/quản lý VPC, ALB, EC2/ASG, IAM role/profile, RDS,
S3, CloudFront, ACM import, CloudWatch và SSM.

Terraform dev hiện dùng local state. Không chạy đồng thời hai lần `plan/apply` trên cùng
environment và không dùng local state cho team hoặc production.

## 2. Build và push API image

Chạy từ root của app repository:

```bash
docker build \
  --platform linux/amd64 \
  -f apps/api/Dockerfile \
  -t trind1/ecommerce-api:<fixed-tag> .

docker push trind1/ecommerce-api:<fixed-tag>
```

Yêu cầu image:

- Có tag cố định, không dùng `latest`.
- Listen trên port `3000`.
- Có thư mục `prisma/migrations`.
- Có npm script `db:deploy` tương ứng với `prisma migrate deploy`.
- Có `apps/api/dist/auth/provision-admin.js`.
- Không chứa `.env`, production password, `SESSION_HMAC_SECRET` hoặc Terraform files.

EC2 sẽ `docker pull` image này trong bootstrap, nên image phải tồn tại trước `apply`.

## 3. Tạo certificate test và cấu hình client CIDR

`dev` dùng self-signed certificate cho ALB HTTPS. Tạo từ infrastructure repository:

```bash
ALB_CERT_DOMAIN=e-commerce-ndt.test \
  ./scripts/generate-alb-self-signed-cert.sh \
  environments/dev/local-certs
```

Certificate phải có SAN `e-commerce-ndt.test`. Private key chỉ giữ local:

```bash
chmod 600 environments/dev/local-certs/alb.key.pem
```

Lấy public IP của máy test, sau đó điền vào `terraform.tfvars`:

```hcl
alb_https_client_cidr_blocks = ["PUBLIC_IP_CUA_BAN/32"]
```

Không mở ALB HTTPS cho `0.0.0.0/0` trong dev test nếu không cần.

## 4. Chuẩn bị Terraform inputs

Tạo file local:

```bash
cp environments/dev/terraform.tfvars.example \
  environments/dev/terraform.tfvars
```

Điền các giá trị deployer cung cấp:

```hcl
application_docker_image = "trind1/ecommerce-api:<fixed-tag>"
database_name            = "ecommerce"
database_username        = "postgres"
database_password        = "<real-database-password>"
api_session_hmac_secret  = "<random-secret-at-least-32-characters>"
```

Tạo session secret bằng:

```bash
openssl rand -hex 32
```

`cloudfront_alb_header_value` là input bắt buộc cho legacy CloudFront/ALB HTTP rule.
Giữ giá trị này trong shell session hiện tại:

```bash
export TF_VAR_cloudfront_alb_header_value="$(openssl rand -hex 32)"
```

Kiểm tra bảo vệ file:

```bash
chmod 600 environments/dev/terraform.tfvars
git check-ignore -v environments/dev/terraform.tfvars
git ls-files | rg '(^|/)(terraform\.tfstate|.*\.tfvars)$'
```

Không commit `terraform.tfvars`, `.tfstate`, `.tfplan`, database password, header secret
hoặc session secret.

## 5. Init, format, validate và tạo plan

Chạy từ root infrastructure repository:

```bash
terraform -chdir=environments/dev init
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan -out=dev.tfplan
terraform -chdir=environments/dev show -no-color dev.tfplan > dev.tfplan.txt
```

Không apply nếu `fmt`, `validate` hoặc `plan` lỗi.

Review plan trước khi apply:

- RDS ở database subnets, không public, port `5432`.
- ALB có HTTPS listener `443` và certificate đúng SAN.
- Target group forward HTTP tới port `3000`.
- Health check dùng `/health` hoặc path đã cấu hình.
- EC2 chỉ nhận traffic từ ALB security group.
- RDS chỉ nhận traffic từ application security group.
- Log groups, IAM role, SSM và ASG được tạo đúng.
- Không có destroy ngoài chủ ý.
- Launch Template thay đổi có thể kích hoạt ASG rolling instance refresh.
- Nếu state cũ có IAM policy Secrets Manager không còn dùng, review destroy đó.

Giữ plan artifact ở nơi bảo mật để review/evidence; không commit vào Git.

## 6. Apply đúng plan đã review

```bash
terraform -chdir=environments/dev apply dev.tfplan
```

Không chạy một `terraform apply` mới khác với plan đã review.

Lấy các output không chứa secret:

```bash
terraform -chdir=environments/dev output -raw alb_dns_name
terraform -chdir=environments/dev output -raw cloudfront_domain_name
terraform -chdir=environments/dev output -raw autoscaling_group_name
terraform -chdir=environments/dev output -raw api_log_group_name
terraform -chdir=environments/dev output -raw rds_address
terraform -chdir=environments/dev output -raw rds_port
```

Không chạy `terraform output` để xuất `DATABASE_URL`, database password hoặc session
secret. Các output đó không được khai báo.

## 7. Cấu hình DNS và trust certificate

Terraform không tạo DNS record cho `e-commerce-ndt.test`. Sau khi có ALB DNS name,
cấu hình local resolver/dnsmasq hoặc DNS provider của bạn để hostname resolve tới ALB.

Test API trước khi cấu hình DNS bằng `curl --connect-to`:

```bash
ALB_DNS="$(terraform -chdir=environments/dev output -raw alb_dns_name)"

curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  https://e-commerce-ndt.test/health
```

Nếu máy test chưa trust self-signed certificate, cài certificate vào trust store hoặc
tạm dùng `-k` cho kiểm tra nhanh. Không dùng `-k` như cấu hình cuối cùng.

## 8. Chờ EC2 và chạy database migration

Không chạy migration trong Docker build hoặc `user_data`. Sau `apply`, ASG phải có ít
nhất một instance `InService`, `Healthy`, SSM `Online` và container `nodejs-api` đang
chạy.

Chạy từ terminal local:

```bash
./scripts/run-db-migration.sh
```

Script tự chọn một instance healthy và gửi:

```bash
docker exec nodejs-api npm run db:deploy
```

Lệnh này áp dụng các migration đã commit trong image vào RDS. Nó không tự tạo migration
từ `schema.prisma`. Nếu migration thất bại, dừng rollout và kiểm tra `DATABASE_URL`,
RDS connectivity, container logs và Prisma schema trước khi retry.

Không để mỗi EC2 trong ASG tự migrate khi boot.

## 9. Provision admin một lần

Chỉ chạy sau khi migration thành công. Tạo file local từ template:

```bash
cp environments/dev/admin-provision.env.example \
  environments/dev/admin-provision.env
chmod 600 environments/dev/admin-provision.env
```

Điền các biến admin vào file local. `ADMIN_PROVISION_TOKEN_HASH` phải được tạo theo
đúng thuật toán mà app `provision-admin.js` yêu cầu.

Chạy từ terminal local:

```bash
./scripts/provision-admin.sh \
  --env-file environments/dev/admin-provision.env
```

Script sẽ chọn một EC2 qua SSM, lấy `DATABASE_URL` từ container đang chạy, tạo file
`/opt/ecommerce/admin-provision.env` với `umask 077` và `chmod 600`, chạy provisioning,
sau đó xóa file tạm trên EC2.

Không chạy đồng thời trên nhiều instance. Sau khi xác nhận admin đăng nhập được, xóa
file secret local nếu không còn cần:

```bash
shred -u environments/dev/admin-provision.env
```

## 10. Build và upload frontend

Chạy từ root của app repository, sau khi biết API domain cố định:

```ini
VITE_API_URL=https://e-commerce-ndt.test/api
```

Build:

```bash
npm run build --workspace=@ecommerce/web
```

Upload từ root infrastructure repository:

```bash
BUCKET="$(terraform -chdir=environments/dev output -raw frontend_bucket_id)"
DIST_ID="$(terraform -chdir=environments/dev output -raw cloudfront_distribution_id)"

aws s3 sync /path/to/app/apps/web/dist/ "s3://${BUCKET}/"
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths '/*'
```

S3 bucket phải giữ private; không bật public access để upload frontend.

## 11. Verification sau deploy

API trực tiếp qua ALB:

```bash
ALB_DNS="$(terraform -chdir=environments/dev output -raw alb_dns_name)"

curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  -i https://e-commerce-ndt.test/health

curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  -i https://e-commerce-ndt.test/ready
```

Kiểm tra target health:

```bash
TARGET_GROUP_ARN="$(terraform -chdir=environments/dev output -raw api_target_group_arn)"
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN"
```

Kiểm tra CloudFront frontend và logs:

```bash
terraform -chdir=environments/dev output -raw cloudfront_domain_name

LOG_GROUP="$(terraform -chdir=environments/dev output -raw api_log_group_name)"
aws logs tail "$LOG_GROUP" --follow --region us-east-1
```

Checklist:

- Frontend mở được qua CloudFront.
- Frontend gọi `https://e-commerce-ndt.test/api`.
- Không lỗi CORS.
- ALB target healthy.
- Container `nodejs-api` listen `0.0.0.0:3000`.
- RDS connection thành công.
- Prisma migration đã applied.
- Admin login thành công.
- CloudWatch có API logs và system logs.
- Không có password, `DATABASE_URL`, session secret hoặc admin token trong logs.

## 12. Rollback và cleanup

Rollback application:

1. Đổi `application_docker_image` về image tag ổn định trước đó.
2. Tạo plan mới.
3. Review plan.
4. Apply plan mới để ASG rolling refresh về image cũ.

Không dùng `terraform destroy` để rollback application. Prisma migration không được
rollback bằng Terraform; cần procedure migration/backup riêng của database.

Sau khi deploy:

- Giữ state local được bảo vệ và không commit.
- Lưu plan/verification evidence ngoài Git nếu cần audit.
- Xóa admin env file local sau khi dùng.
- Không xóa RDS hoặc chạy destroy khi chưa xác nhận snapshot, backup và blast radius.
