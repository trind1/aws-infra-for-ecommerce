# Runbook triển khai `dev`

Tài liệu này mô tả các bước chuẩn bị, apply và verification cho
`environments/dev`. Không ghi password, session secret, private key hoặc state thật vào
tài liệu này.

## Kiến trúc

```text
Browser → CloudFront → S3 private + OAC
Browser → e-commerce-ndt.test → ALB HTTPS :443 → EC2 Docker :3000 → RDS :5432
```

CloudFront chỉ phục vụ frontend; API không proxy qua CloudFront.

## 1. Chuẩn bị trước Terraform

### Docker image

Chạy từ root của app repository:

```bash
docker build \
  --platform linux/amd64 \
  -f apps/api/Dockerfile \
  -t trind1/ecommerce-api:<fixed-tag> .
docker push trind1/ecommerce-api:<fixed-tag>
```

Image phải tồn tại trước khi EC2 bootstrap chạy `docker pull`. Không dùng `latest`.
`.dockerignore` phải loại `.env`, `.env.*`, certificate, private key và Terraform files.

### Certificate và client CIDR

Certificate phải có SAN `e-commerce-ndt.test` và hai file local phải tồn tại:

```text
environments/dev/local-certs/alb.crt.pem
environments/dev/local-certs/alb.key.pem
```

`alb_https_client_cidr_blocks` phải chứa public IP máy test, thường là `PUBLIC_IP/32`.
Certificate self-signed cần được trust trên máy client sau khi apply.

### Input local

Sửa file không commit:

```text
environments/dev/terraform.tfvars
```

Thay các placeholder:

```hcl
application_docker_image = "trind1/ecommerce-api:<fixed-tag>"
database_name            = "ecommerce"
database_username        = "postgres"
database_password        = "<real-database-password>"
api_session_hmac_secret  = "<random-secret-at-least-32-characters>"
```

Legacy HTTP CloudFront listener vẫn được giữ để rollback nên hiện tại cần custom header:

```bash
export TF_VAR_cloudfront_alb_header_value="$(openssl rand -hex 32)"
```

Bảo vệ input file và kiểm tra Git ignore:

```bash
chmod 600 environments/dev/terraform.tfvars
git check-ignore -v environments/dev/terraform.tfvars
git ls-files | rg '(^|/)(terraform\.tfstate|.*\.tfvars)$'
```

State hiện là local state của `dev`; không commit `.tfstate`, `.tfplan` hoặc plan output.

## 2. Init, validate và tạo plan

Chạy từ repository root:

```bash
terraform version
terraform -chdir=environments/dev init
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan -out=dev.tfplan
terraform -chdir=environments/dev show -no-color dev.tfplan > dev.tfplan.txt
```

Không apply nếu `validate` hoặc `plan` lỗi.

Review `dev.tfplan.txt`:

- RDS nằm trong private subnets, không public, port `5432`.
- ALB có HTTPS `443` với certificate đúng SAN.
- Target group dùng HTTP `3000`, health check `/health`.
- EC2 chỉ nhận traffic từ ALB security group.
- RDS chỉ nhận traffic từ application security group.
- Không có destroy ngoài chủ ý.
- Launch Template update có thể kích hoạt ASG instance refresh.
- Nếu state cũ có `aws_iam_role_policy.database_secret`, việc bỏ contract này có thể
  destroy policy và phải được review.

Giữ lại plan artifact để làm evidence; không commit.

## 3. Apply đúng plan

```bash
terraform -chdir=environments/dev apply dev.tfplan
```

Không chạy `terraform apply` trực tiếp sau khi đã review một plan khác.

Lấy output sau apply:

```bash
terraform -chdir=environments/dev output -raw alb_dns_name
terraform -chdir=environments/dev output -raw cloudfront_domain_name
terraform -chdir=environments/dev output -raw api_log_group_name
terraform -chdir=environments/dev output -raw autoscaling_group_name
terraform -chdir=environments/dev output -raw rds_address
```

Không output password, `DATABASE_URL` hoặc session secret.

## 4. Local DNS và certificate

`e-commerce-ndt.test` là local domain; Terraform không tạo public DNS record. Sau khi có
`alb_dns_name`, cấu hình local DNS/dnsmasq trỏ domain tới ALB DNS.

Test nhanh trước khi cấu hình DNS:

```bash
ALB_DNS="$(terraform -chdir=environments/dev output -raw alb_dns_name)"
curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  https://e-commerce-ndt.test/health
```

Chỉ dùng `-k` tạm thời nếu self-signed certificate chưa được trust.

## 5. Migration và admin provisioning

Không chạy migration trong Docker build hoặc trong `user_data`. Sau khi `apply` hoàn tất,
chờ ít nhất một instance ở trạng thái `InService`, SSM `Online` và container
`nodejs-api` đang chạy.

Lấy một instance duy nhất trong ASG:

```bash
ASG_NAME="$(terraform -chdir=environments/dev output -raw autoscaling_group_name)"

INSTANCE_ID="$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`].InstanceId | [0]' \
  --output text)"

test -n "$INSTANCE_ID" && test "$INSTANCE_ID" != "None"

aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text
```

Chạy script post-apply từ repository root. Script sẽ gửi migration qua SSM
đến đúng một instance và chờ kết quả:

```bash
./scripts/run-db-migration.sh
```

Script kiểm tra container rồi chạy `docker exec nodejs-api npm run db:deploy`.
Nếu migration thất bại, dừng rollout và kiểm tra container, `DATABASE_URL`, RDS
connectivity và Prisma schema trước khi retry. Không để mỗi EC2 trong ASG tự migrate
khi boot.

Admin provisioning chỉ chạy sau migration thành công. Tạo file local từ template,
thay placeholder bằng giá trị thật và bảo vệ file:

```bash
cp environments/dev/admin-provision.env.example environments/dev/admin-provision.env
chmod 600 environments/dev/admin-provision.env
```

Sau đó chạy script. Script gửi provisioning đến một instance qua SSM, lấy
`DATABASE_URL` từ container đang chạy, tạo file tạm trên EC2 với
`umask 077`/`chmod 600`, rồi xóa file sau khi hoàn tất:

```bash
./scripts/provision-admin.sh \
  --env-file environments/dev/admin-provision.env
```

Script dùng đúng image đang chạy của container `nodejs-api`, nên không hardcode tag.
Không chạy script đồng thời trên nhiều instance. Không ghi admin password hoặc token
vào shell history, Terraform state, Docker image hay log.

## 6. Frontend

Tại app repository, tạo local `.env.production`:

```ini
VITE_API_URL=https://e-commerce-ndt.test/api
```

Build và upload:

```bash
npm run build --workspace=@ecommerce/web

BUCKET="$(terraform -chdir=environments/dev output -raw frontend_bucket_id)"
DIST_ID="$(terraform -chdir=environments/dev output -raw cloudfront_distribution_id)"
aws s3 sync apps/web/dist/ "s3://$BUCKET/"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths '/*'
```

## 7. Verification

```bash
curl -i https://e-commerce-ndt.test/health
curl -i https://e-commerce-ndt.test/ready
```

Kiểm tra:

- ALB target healthy.
- Container `nodejs-api` đang chạy và listen `0.0.0.0:3000`.
- RDS connection thành công.
- Migration đã applied.
- Frontend mở được qua CloudFront và gọi đúng API domain.
- CORS cho phép đúng CloudFront origin.
- Không có password, session secret hoặc `DATABASE_URL` trong logs.

CloudWatch:

```bash
LOG_GROUP="$(terraform -chdir=environments/dev output -raw api_log_group_name)"
aws logs tail "$LOG_GROUP" --follow --region us-east-1
```

## 8. Rollback và evidence

- Giữ `dev.tfplan`, `dev.tfplan.txt` và verification output ngoài Git ở nơi bảo mật.
- Rollback application bằng image tag trước đó, tạo plan mới và review trước khi apply.
- Không rollback Prisma schema bằng Terraform; migration rollback cần procedure và backup
  database riêng.
- Không dùng `terraform destroy` để rollback application.
- Runbook này chưa thực hiện `apply` và chưa tạo state mutation.
