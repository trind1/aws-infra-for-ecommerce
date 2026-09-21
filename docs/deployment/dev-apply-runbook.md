# Dev deployment runbook

Runbook này mô tả toàn bộ quy trình triển khai `environments/dev`: chuẩn bị artifact,
kiểm tra Terraform, apply hạ tầng, chạy migration/provision admin và verification.

Không đặt password, session secret, admin secret, private key hoặc Terraform state thật
trong tài liệu này. Các lệnh được chạy từ root của infrastructure repository, trừ khi
ghi rõ là chạy từ app repository.

## Bắt đầu nhanh và tiêu chí hoàn tất

Đây là file runbook chính cho lần deploy `dev`; `README.md` ở root đã link trực tiếp tới
file này. Luồng triển khai gồm các gate sau:

```text
App image + certificate + inputs
        ↓
Terraform init → fmt → validate → plan → review
        ↓
Apply đúng plan đã review
        ↓
ALB/ASG/SSM/RDS healthy
        ↓
Migration một lần → provision admin một lần
        ↓
Upload frontend → smoke test API/frontend/logs
```

Chỉ coi deployment thành công khi tất cả gate trên đạt. `terraform validate` chỉ xác nhận
syntax/provider schema; không thay thế `plan`, kiểm tra AWS runtime, migration hoặc smoke
test ứng dụng.

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
terraform fmt -check -recursive modules
terraform fmt -check environments/dev/*.tf
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan -out=dev.tfplan
terraform -chdir=environments/dev show -no-color dev.tfplan > dev.tfplan.txt
```

Format check chỉ chạy trên source `.tf`; không format tự động `terraform.tfvars` thật vì file
local này có thể chứa secret và không được commit.

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

`api_database_url` không phải output để lấy bằng CLI. Environment dựng nó từ RDS address,
port, database name và credentials tại `environments/dev/main.tf`, sau đó truyền sensitive
vào compute/user data. Vì vậy chỉ verify gián tiếp bằng RDS connectivity, target health,
container health và migration; không in `DATABASE_URL` hoặc password ra terminal/log.

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

Baseline cần ghi lại sau `apply`:

| Output | Kết quả mong đợi |
|---|---|
| `alb_dns_name` | Có DNS name của internet-facing ALB. |
| `api_target_group_arn` | Có ARN target group API để kiểm tra target health. |
| `autoscaling_group_name` | Có ASG name; ASG có instance `InService`/`Healthy`. |
| `cloudfront_domain_name` | Có domain `*.cloudfront.net` phục vụ frontend. |
| `frontend_bucket_id` | Có S3 bucket private do Terraform quản lý. |
| `rds_identifier`, `rds_address`, `rds_port` | RDS tồn tại, private, đúng port; không chứa credential. |
| `api_log_group_name`, `system_log_group_name` | Có CloudWatch log groups để kiểm tra bootstrap/API. |

Nếu output rỗng hoặc command trả `No state`, dừng quy trình và kiểm tra đúng thư mục
`environments/dev`, đúng state và đúng AWS account trước khi chạy lại.

## 7. Cấu hình DNS và trust certificate

Terraform không tạo DNS record cho `e-commerce-ndt.test`. Sau khi có ALB DNS name,
cấu hình local resolver/dnsmasq hoặc DNS provider của bạn để hostname resolve tới ALB.

Test API trước khi cấu hình DNS bằng `curl --connect-to`:

```bash
ALB_DNS="$(terraform -chdir=environments/dev output -raw alb_dns_name)"
API_HEALTH_PATH="${API_HEALTH_PATH:-/api/health}"

curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  "https://e-commerce-ndt.test${API_HEALTH_PATH}"
```

`API_HEALTH_PATH` phải là route public của app và nằm dưới `/api` hoặc `/api/*`; listener
HTTPS hiện tại chỉ forward hai path này. `/health` là health check nội bộ giữa ALB và target
port `3000`, không mặc định là route public của ALB.

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

## 10. Build và publish frontend (Cái này chạy bên App repo)

Chạy từ root của app repository, sau khi biết API domain cố định:

Build bằng production API origin. Với `dev` hiện tại, origin là
`https://e-commerce-ndt.test/api`; thay bằng API origin của environment đang deploy nếu
khác:

```bash
# Ví dụ khi API production là api.example.com:
# VITE_API_URL=https://api.example.com/api npm run build

VITE_API_URL="${VITE_API_URL:-https://e-commerce-ndt.test/api}" \
  npm run build --workspace=@ecommerce/web

test -f apps/web/dist/index.html
```

Output build phải là `apps/web/dist`; chỉ upload thư mục này, không upload source hoặc file
local khác. Chuyển về root infrastructure repository để lấy bucket/distribution từ Terraform:

```bash
BUCKET="$(terraform -chdir=environments/dev output -raw frontend_bucket_id)"
DIST_ID="$(terraform -chdir=environments/dev output -raw cloudfront_distribution_id)"
CF_DOMAIN="$(terraform -chdir=environments/dev output -raw cloudfront_domain_name)"

test -n "$BUCKET" && test -n "$DIST_ID"
aws s3api head-bucket --bucket "$BUCKET"
printf 'Terraform frontend bucket: s3://%s\n' "$BUCKET"
read -r -p 'Nhập lại chính xác bucket name để xác nhận --delete: ' CONFIRMED_BUCKET
test "$CONFIRMED_BUCKET" = "$BUCKET"

FRONTEND_DIST="/path/to/app/apps/web/dist"
test -f "$FRONTEND_DIST/index.html"

aws s3 sync "$FRONTEND_DIST" "s3://${BUCKET}" \
  --delete \
  --cache-control 'public,max-age=31536000,immutable' \
  --exclude 'index.html'

aws s3 cp "$FRONTEND_DIST/index.html" "s3://${BUCKET}/index.html" \
  --cache-control 'no-cache,no-store,must-revalidate' \
  --content-type 'text/html; charset=utf-8'

aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths '/*'
```

Không chạy `--delete` trước khi kiểm tra bucket output và xác nhận interactive ở trên. S3
bucket phải giữ private; không bật public access để upload frontend. CloudFront OAC là
đường đọc duy nhất từ CloudFront tới bucket.

CloudFront phải có SPA fallback: request tới client-side route không tồn tại trong S3 phải
được trả nội dung `index.html` với HTTP `200`. Cấu hình này được tạo bởi module frontend;
vẫn cần kiểm tra lại sau `apply`.

## 11. Verification sau deploy

### 11.1 Kiểm tra hạ tầng và runtime

Kiểm tra ASG, instance health, SSM và RDS trước khi kiểm tra ứng dụng:

```bash
ASG_NAME="$(terraform -chdir=environments/dev output -raw autoscaling_group_name)"
DB_ID="$(terraform -chdir=environments/dev output -raw rds_identifier)"

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:Instances[*].{Id:InstanceId,State:LifecycleState,Health:HealthStatus}}'

aws ssm describe-instance-information \
  --filters "Key=ResourceType,Values=ManagedInstance" \
  --query 'InstanceInformationList[*].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName}'

aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Public:PubliclyAccessible,Port:Endpoint.Port,Address:Endpoint.Address}'
```

Kết quả đạt khi ASG có instance `InService` và `Healthy`, instance cần dùng cho migration có
SSM `Online`, RDS `Status=available`, `Public=false`, và port khớp `rds_port` (mặc định `5432`).

### 11.2 Kiểm tra ALB target và API

```bash
ALB_DNS="$(terraform -chdir=environments/dev output -raw alb_dns_name)"
API_HEALTH_PATH="${API_HEALTH_PATH:-/api/health}"

curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  -i "https://e-commerce-ndt.test${API_HEALTH_PATH}"
```

Kiểm tra target health:

```bash
TARGET_GROUP_ARN="$(terraform -chdir=environments/dev output -raw api_target_group_arn)"
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN"
```

Target phải có `TargetHealth.State=healthy`; HTTP smoke test phải trả status thuộc contract
của app (thường `200`). Nếu target `unhealthy`, kiểm tra `cloud-init-output.log`, container
status/logs, port `3000`, security group ALB → app và health check path `/health`.

### 11.3 Kiểm tra frontend, logs và alarms

```bash
terraform -chdir=environments/dev output -raw cloudfront_domain_name

LOG_GROUP="$(terraform -chdir=environments/dev output -raw api_log_group_name)"
aws logs tail "$LOG_GROUP" --follow --region us-east-1
```

Khi kiểm tra frontend, dùng domain CloudFront lấy từ output và kỳ vọng HTTP `200` hoặc
redirect hợp lệ:

```bash
CF_DOMAIN="$(terraform -chdir=environments/dev output -raw cloudfront_domain_name)"
curl -I "https://${CF_DOMAIN}/"
curl -fsS -o /tmp/frontend-spa-fallback.html -w 'SPA fallback HTTP %{http_code}\n' \
  "https://${CF_DOMAIN}/routes/that-do-not-exist"

BUCKET="$(terraform -chdir=environments/dev output -raw frontend_bucket_id)"
DIST_ID="$(terraform -chdir=environments/dev output -raw cloudfront_distribution_id)"
OAC_ID="$(terraform -chdir=environments/dev output -raw frontend_origin_access_control_id)"

aws s3api get-public-access-block --bucket "$BUCKET"
aws s3api get-bucket-policy-status --bucket "$BUCKET"
aws cloudfront get-distribution --id "$DIST_ID" \
  --query 'Distribution.DistributionConfig.Origins.Items[0].OriginAccessControlId'
printf 'Expected OAC: %s\n' "$OAC_ID"

terraform -chdir=environments/dev output -json monitoring_alarm_names
```

SPA fallback đạt khi deep-link trả HTTP `200` và nội dung giống frontend `index.html`; public
access block có đủ bốn flag `true`, bucket policy status là `IsPublic=false`, và
`OriginAccessControlId` của CloudFront khớp output Terraform.

Không copy nội dung log chứa secret vào ticket hoặc plan artifact. Nếu cần xem log realtime,
dừng `aws logs tail --follow` sau khi xác nhận và kiểm tra không có `DATABASE_URL`, password,
session secret hoặc admin token.

Checklist:

- Frontend mở được qua CloudFront.
- API public route nằm dưới `https://e-commerce-ndt.test/api` và smoke test trả kết quả hợp lệ.
- Không lỗi CORS.
- ALB target healthy.
- Container `nodejs-api` listen `0.0.0.0:3000`.
- RDS connection thành công.
- Prisma migration đã applied.
- Admin login thành công.
- CloudWatch có API logs và system logs.
- Không có password, `DATABASE_URL`, session secret hoặc admin token trong logs.

## 12. Kịch bản test và evidence

Checklist sign-off tập trung nằm tại
[dev-verification-test-plan.md](dev-verification-test-plan.md). Phần dưới đây giữ các
command chi tiết để có thể chạy ngay trong cùng deployment session.

### 12.1 Phân biệt output và evidence

Terraform output chỉ là reference để truy vấn resource; output có giá trị không chứng minh
resource đang healthy. Một deployment chỉ đạt khi có đủ cả ba lớp bằng chứng:

```text
Terraform output
        +
AWS control-plane status
        +
Runtime smoke test và application logs
        =
Evidence deployment hợp lệ
```

Không lưu password, `DATABASE_URL`, session secret, admin token, private key hoặc toàn bộ
Terraform state vào evidence. Evidence nên lưu ngoài Git:

```bash
EVIDENCE_DIR="/tmp/ecommerce-dev-evidence-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR"
echo "Evidence directory: $EVIDENCE_DIR"
```

### 12.2 Test matrix

| ID | Test | Lệnh/điểm kiểm tra | Kết quả đạt | Evidence cần giữ |
|---|---|---|---|---|
| T0 | Đúng account/state | `aws sts get-caller-identity`; đọc các Terraform outputs | Account, state và region đúng; output không rỗng | `preflight.txt` |
| T1 | Không còn drift | `terraform plan -detailed-exitcode -out=post-deploy.tfplan` | Exit `0`, không có thay đổi ngoài chủ ý | Plan reviewed, không commit |
| T2 | RDS/private boundary | `aws rds describe-db-instances` | `available`, `Public=false`, port đúng | `rds.json` |
| T3 | ASG/EC2/SSM | `describe-auto-scaling-groups`, `describe-instance-information` | Instance `InService`, `Healthy`, SSM `Online` | `compute.json` |
| T4 | ALB target/API | `describe-target-health`, `curl` public API route | Target `healthy`, HTTP status theo app contract, thường `200` | `target-health.json`, `api-response.txt` |
| T5 | Database migration | `./scripts/run-db-migration.sh` | Script exit `0`, command status `Success` | Output đã redact secret |
| T6 | Admin provisioning | `./scripts/provision-admin.sh --env-file ...` | Script exit `0`, login admin thành công | Output đã redact secret + functional check |
| T7 | Frontend/index cache | `curl -I` CloudFront `/`, `head-object` `index.html` | Index `200`, `Cache-Control: no-cache...` | `frontend-headers.txt` |
| T8 | SPA fallback | `curl` một deep-link không tồn tại trong S3 | HTTP `200`, body là `index.html` | `spa-fallback.html`, status output |
| T9 | S3 private/OAC | Public access block, policy status, OAC ID, direct S3 request | 4 flags `true`, `IsPublic=false`, OAC khớp, direct S3 bị `403` | `bucket-public-access-block.json`, `bucket-policy-status.json`, `direct-s3-status.txt`, `oac.txt` |
| T10 | Logs/alarms | CloudWatch API/system logs và alarm names | Có log sau request; alarm ở trạng thái phù hợp | `log-streams.json`, `alarm-names.json`, `active-alarms.json` |

### 12.3 Lệnh test và output kỳ vọng

Preflight và Terraform drift check:

```bash
set -euo pipefail

AWS_PAGER="" aws sts get-caller-identity | tee "$EVIDENCE_DIR/preflight.txt"

for output_name in \
  alb_dns_name \
  api_target_group_arn \
  autoscaling_group_name \
  frontend_bucket_id \
  cloudfront_distribution_id \
  cloudfront_domain_name \
  frontend_origin_access_control_id \
  rds_identifier \
  rds_address \
  rds_port; do
  printf '%s=' "$output_name" >> "$EVIDENCE_DIR/terraform-outputs.txt"
  terraform -chdir=environments/dev output -raw "$output_name" \
    >> "$EVIDENCE_DIR/terraform-outputs.txt"
done

if terraform -chdir=environments/dev plan \
  -detailed-exitcode \
  -out=post-deploy.tfplan; then
  plan_status=0
else
  plan_status=$?
fi
printf 'terraform plan exit=%s\n' "$plan_status" | tee "$EVIDENCE_DIR/plan-status.txt"
test "$plan_status" -eq 0
```

Expected: account ID đúng, tất cả output không rỗng, `terraform plan` exit `0`. Exit `2`
nghĩa là còn drift/change cần review; không tự động coi là pass và không apply lại nếu chưa
review plan mới.

Runtime/resource checks:

```bash
ASG_NAME="$(terraform -chdir=environments/dev output -raw autoscaling_group_name)"
DB_ID="$(terraform -chdir=environments/dev output -raw rds_identifier)"
TARGET_GROUP_ARN="$(terraform -chdir=environments/dev output -raw api_target_group_arn)"
ALB_DNS="$(terraform -chdir=environments/dev output -raw alb_dns_name)"
API_HEALTH_PATH="${API_HEALTH_PATH:-/api/health}"

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[*].{Id:InstanceId,State:LifecycleState,Health:HealthStatus}}' \
  | tee "$EVIDENCE_DIR/compute.json"

aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].{Id:InstanceId,Ping:PingStatus,Platform:PlatformName}' \
  | tee "$EVIDENCE_DIR/ssm.json"

aws rds describe-db-instances \
  --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Public:PubliclyAccessible,Port:Endpoint.Port,Address:Endpoint.Address}' \
  | tee "$EVIDENCE_DIR/rds.json"

aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN" \
  | tee "$EVIDENCE_DIR/target-health.json"

curl --connect-to e-commerce-ndt.test:443:"$ALB_DNS":443 \
  -i "https://e-commerce-ndt.test${API_HEALTH_PATH}" \
  | tee "$EVIDENCE_DIR/api-response.txt"
```

Expected tối thiểu: `State=InService`, `Health=Healthy`, `Ping=Online`, RDS
`Status=available`, `Public=false`, và mọi target có `TargetHealth.State=healthy`.

Frontend/security checks:

```bash
CF_DOMAIN="$(terraform -chdir=environments/dev output -raw cloudfront_domain_name)"
BUCKET="$(terraform -chdir=environments/dev output -raw frontend_bucket_id)"
DIST_ID="$(terraform -chdir=environments/dev output -raw cloudfront_distribution_id)"
OAC_ID="$(terraform -chdir=environments/dev output -raw frontend_origin_access_control_id)"
AWS_REGION="${AWS_REGION:-us-east-1}"

curl -sS -D "$EVIDENCE_DIR/frontend-headers.txt" -o /dev/null \
  "https://${CF_DOMAIN}/"
curl -fsS -D "$EVIDENCE_DIR/spa-headers.txt" \
  -o "$EVIDENCE_DIR/spa-fallback.html" \
  "https://${CF_DOMAIN}/routes/that-do-not-exist"

aws s3api head-object --bucket "$BUCKET" --key index.html \
  | tee "$EVIDENCE_DIR/index-object.json"
aws s3api get-public-access-block --bucket "$BUCKET" \
  | tee "$EVIDENCE_DIR/bucket-public-access-block.json"
aws s3api get-bucket-policy-status --bucket "$BUCKET" \
  | tee "$EVIDENCE_DIR/bucket-policy-status.json"
aws cloudfront get-distribution --id "$DIST_ID" \
  --query 'Distribution.DistributionConfig.Origins.Items[0].OriginAccessControlId' \
  | tee "$EVIDENCE_DIR/oac.txt"
printf 'Expected OAC: %s\n' "$OAC_ID" | tee -a "$EVIDENCE_DIR/oac.txt"

S3_PUBLIC_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' \
  "https://${BUCKET}.s3.${AWS_REGION}.amazonaws.com/index.html")"
printf 'Direct S3 unauthenticated HTTP status: %s\n' "$S3_PUBLIC_STATUS" \
  | tee "$EVIDENCE_DIR/direct-s3-status.txt"
test "$S3_PUBLIC_STATUS" = "403"

LOG_GROUP="$(terraform -chdir=environments/dev output -raw api_log_group_name)"
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --order-by LastEventTime \
  --descending \
  --max-items 5 \
  | tee "$EVIDENCE_DIR/log-streams.json"
terraform -chdir=environments/dev output -json monitoring_alarm_names \
  | tee "$EVIDENCE_DIR/alarm-names.json"
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
  | tee "$EVIDENCE_DIR/active-alarms.json"
```

Expected: CloudFront `/` và deep-link đều trả `200`; `index.html` có
`Cache-Control: no-cache,no-store,must-revalidate`; public access block đủ bốn flag `true`;
`IsPublic=false`; OAC runtime khớp Terraform output. Direct S3 object request từ Internet
phải bị từ chối (`403`), còn CloudFront vẫn đọc được object qua OAC.

### 12.4 Cách kết luận test

- `Pass`: command exit `0` và output đạt expected result đã nêu.
- `Fail`: resource/runtime trả kết quả sai; giữ nguyên command output và dừng rollout.
- `Blocked`: thiếu credential, provider, network hoặc app artifact; ghi nguyên nhân cụ thể.
- `Chưa xác minh`: chưa chạy command, không gọi là Pass.

Deployment chỉ được sign-off khi T0–T10 đều `Pass`, không có secret trong evidence, và
`post-deploy.tfplan` đã được review/lưu ở nơi bảo mật.

## 13. Rollback và cleanup

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
