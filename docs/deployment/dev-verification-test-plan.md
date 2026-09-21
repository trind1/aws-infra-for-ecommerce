# Dev verification test plan

Tài liệu này là checklist sign-off sau khi triển khai `environments/dev`. Quy trình deploy và command chi tiết nằm ở [dev-apply-runbook.md](dev-apply-runbook.md).

## Nguyên tắc

Terraform output chỉ là reference; không chứng minh resource đang healthy. Evidence hợp lệ phải kết hợp Terraform output, AWS control-plane status và runtime smoke test/logs.

Không lưu password, `DATABASE_URL`, session secret, admin token, private key hoặc Terraform state vào evidence. Tạo thư mục evidence ngoài Git:

```bash
EVIDENCE_DIR="/tmp/ecommerce-dev-evidence-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$EVIDENCE_DIR"
chmod 700 "$EVIDENCE_DIR"
```

## 1. Terraform outputs cần kiểm tra

Chạy `terraform -chdir=environments/dev output -raw <name>` cho các output sau:

| Output | Mục đích | Expected |
|---|---|---|
| `alb_dns_name` | Gọi API qua ALB | Không rỗng, đúng ALB |
| `api_target_group_arn` | Kiểm tra target health | ARN hợp lệ |
| `autoscaling_group_name` | Kiểm tra EC2/ASG/SSM | ASG name hợp lệ |
| `frontend_bucket_id` | Upload frontend | Đúng bucket Terraform cấp |
| `cloudfront_distribution_id` | Invalidation/query CloudFront | Distribution ID hợp lệ |
| `cloudfront_domain_name` | Kiểm tra frontend/SPA | Domain `*.cloudfront.net` |
| `frontend_origin_access_control_id` | Đối chiếu OAC runtime | Khớp CloudFront config |
| `rds_identifier` | Query RDS status | DB identifier hợp lệ |
| `rds_address`, `rds_port` | Đối chiếu connectivity | Endpoint có port đúng, mặc định `5432` |

Không có output cho `DATABASE_URL`, database password hoặc `SESSION_HMAC_SECRET`; đây là chủ ý. Các giá trị này được verify gián tiếp qua RDS connectivity, container health và migration.

## 2. Test matrix

| ID | Test | Command/điểm kiểm tra | Pass condition | Evidence |
|---|---|---|---|---|
| T0 | AWS identity/state | `aws sts get-caller-identity`, Terraform outputs | Đúng account/region/state; output không rỗng | `preflight.txt`, `terraform-outputs.txt` |
| T1 | Terraform drift | `terraform plan -detailed-exitcode` | Exit `0`, không có change ngoài chủ ý | `post-deploy.tfplan` |
| T2 | RDS/private boundary | `aws rds describe-db-instances` | `available`, `Public=false`, port đúng | `rds.json` |
| T3 | ASG/SSM | `describe-auto-scaling-groups`, `describe-instance-information` | `InService`, `Healthy`, `Online` | `compute.json`, `ssm.json` |
| T4 | ALB target | `aws elbv2 describe-target-health` | Mọi target `healthy` | `target-health.json` |
| T5 | API smoke test | `curl` public API route | Status theo app contract, thường `200` | `api-response.txt` |
| T6 | Database migration | `./scripts/run-db-migration.sh` | Exit `0`, SSM command `Success` | Output đã redact secret |
| T7 | Admin provisioning | `./scripts/provision-admin.sh --env-file ...` | Exit `0`, login admin thành công | Functional check |
| T8 | Frontend/cache | `curl -I` CloudFront, `head-object` | `/` trả `200`; `index.html` no-cache | `frontend-headers.txt`, `index-object.json` |
| T9 | SPA fallback | Gọi deep-link không tồn tại trong S3 | HTTP `200`, body là `index.html` | `spa-fallback.html` |
| T10 | S3 private/OAC | Public access, policy, OAC, direct S3 | 4 flags `true`, `IsPublic=false`, OAC khớp, direct S3 `403` | `bucket-*.json`, `direct-s3-status.txt`, `oac.txt` |
| T11 | Logs/alarms | CloudWatch logs/alarms | Có log sau request, không alarm bất thường | `log-streams.json`, `active-alarms.json` |

## 3. Expected output quan trọng

```text
ASG:        LifecycleState=InService, HealthStatus=Healthy
SSM:        PingStatus=Online
RDS:        DBInstanceStatus=available, PubliclyAccessible=false
ALB:        TargetHealth.State=healthy
API:        HTTP 200 hoặc status đúng application contract
CloudFront: / và deep-link HTTP 200
S3:         PublicAccessBlock=true, IsPublic=false, direct request=403
Terraform:  plan -detailed-exitcode exit 0
```

Chi tiết command đầy đủ nằm trong phần [Kịch bản test và evidence](dev-apply-runbook.md#12-kịch-bản-test-và-evidence) của runbook.

## 4. Sign-off criteria

- Tất cả T0–T11 đều `Pass`.
- Không có secret trong evidence, terminal capture hoặc CloudWatch logs.
- `post-deploy.tfplan` đã được review và lưu ở nơi bảo mật.
- Nếu có `Fail` hoặc `Blocked`, dừng sign-off và ghi nguyên nhân, owner, remediation.

Trạng thái runtime hiện tại: `Chưa xác minh` cho tới khi chạy trên AWS account thật.

## 5. Kịch bản system test

System test xác nhận AWS resource, network boundary và runtime infrastructure; không thay thế functional test của application.

### SYS-01 — Terraform state và drift

- Đọc toàn bộ output ở mục 1.
- Chạy `terraform -chdir=environments/dev plan -detailed-exitcode -out=post-deploy.tfplan`.
- Expected: exit `0`; exit `2` là còn drift/change cần review.
- Evidence: `terraform-outputs.txt`, `post-deploy.tfplan`, `plan-status.txt`.

### SYS-02 — Network và security boundary

Lấy các security group ID từ Terraform output rồi lưu rule thực tế:

```bash
for output_name in alb_security_group_id application_security_group_id database_security_group_id; do
  terraform -chdir=environments/dev output -raw "$output_name"
done

ALB_SG_ID="$(terraform -chdir=environments/dev output -raw alb_security_group_id)"
APPLICATION_SG_ID="$(terraform -chdir=environments/dev output -raw application_security_group_id)"
DATABASE_SG_ID="$(terraform -chdir=environments/dev output -raw database_security_group_id)"

aws ec2 describe-security-groups --group-ids \
  "$ALB_SG_ID" "$APPLICATION_SG_ID" "$DATABASE_SG_ID" \
  > "$EVIDENCE_DIR/security-groups.json"
```

Expected:

- ALB HTTPS chỉ mở cho client CIDR đã khai báo.
- Application port `3000` chỉ nhận từ ALB security group.
- Database port `5432` chỉ nhận từ application security group.
- Không có ingress Internet trực tiếp vào app `3000` hoặc database `5432`.

### SYS-03 — Compute, SSM, ALB và RDS

Chạy các lệnh ở mục 3 để xác nhận ASG, SSM, RDS và target group. Expected đồng thời:

```text
ASG instance: InService + Healthy
SSM:          Online
RDS:          available + Public=false
ALB target:   healthy
```

Nếu target unhealthy, dừng app rollout và kiểm tra `cloud-init-output.log`, Docker container, port `3000`, health check `/health`, SG ALB → app và app → RDS.

### SYS-04 — Frontend delivery, SPA và OAC

- CloudFront `/` trả HTTP `200`.
- Một deep-link không tồn tại trong S3 trả HTTP `200` và body là `index.html`.
- `index.html` có `Cache-Control: no-cache,no-store,must-revalidate`.
- Static assets có cache immutable.
- S3 Public Access Block đủ bốn flag `true`.
- `IsPublic=false` và direct unauthenticated S3 request trả `403`.
- `OriginAccessControlId` runtime khớp Terraform output.

### SYS-05 — Observability và operational readiness

- Sau một API request có API log stream mới hoặc log event tương ứng.
- Có system/bootstrap log để điều tra instance lỗi.
- Không có `DATABASE_URL`, password, session secret hoặc admin token trong log.
- Không có CloudWatch alarm bất thường sau smoke test.
- Không thực hiện terminate instance, destroy RDS hoặc test failover trong kịch bản này nếu chưa có maintenance window và approval riêng.

## 6. Kịch bản application test

Application test phải chạy sau SYS-01 đến SYS-04 đạt. Các endpoint nghiệp vụ không được định nghĩa trong repository infra; app team phải thay placeholder bằng contract thật trước khi sign-off.

### APP-01 — Build artifact và cấu hình API origin

Chạy từ app repository:

```bash
VITE_API_URL="${VITE_API_URL:-https://e-commerce-ndt.test/api}" \
  npm run build --workspace=@ecommerce/web
test -f apps/web/dist/index.html
```

Expected: build thành công, `apps/web/dist/index.html` tồn tại, frontend được build với API origin đúng environment. Không dùng `latest` hoặc API origin của environment khác.

Evidence: build log, commit/tag app, API origin đã dùng; không lưu secret.

### APP-02 — API liveness và database readiness

Đặt public health route theo application contract. Mặc định dưới đây chỉ là ví dụ của dev:

```bash
API_BASE_URL="https://e-commerce-ndt.test/api"
APP_HEALTH_PATH="${APP_HEALTH_PATH:-/health}"
APP_READINESS_PATH="${APP_READINESS_PATH:-/ready}"

curl -fsS -i "${API_BASE_URL}${APP_HEALTH_PATH}" \
  | tee "$EVIDENCE_DIR/app-health.txt"
curl -fsS -i "${API_BASE_URL}${APP_READINESS_PATH}" \
  | tee "$EVIDENCE_DIR/app-readiness.txt"
```

Expected: health trả status theo contract, thường `200`; readiness chỉ pass khi app xác nhận kết nối RDS/migration hợp lệ. Nếu app không có `/ready`, ghi `Not applicable` và thay bằng một API read-only có query database.

### APP-03 — CORS và API routing

Dùng một API route hợp lệ đã được app team chỉ định:

```bash
APP_CORS_TEST_PATH="${APP_CORS_TEST_PATH:-/health}"
FRONTEND_ORIGIN="https://<cloudfront-domain>"

curl -i -X OPTIONS "${API_BASE_URL}${APP_CORS_TEST_PATH}" \
  -H "Origin: ${FRONTEND_ORIGIN}" \
  -H 'Access-Control-Request-Method: GET' \
  | tee "$EVIDENCE_DIR/cors-preflight.txt"
```

Expected: `Access-Control-Allow-Origin` khớp chính xác frontend origin; không dùng `*` nếu app dùng credentials. Request ngoài allowlist phải không được cấp CORS origin.

### APP-04 — Authentication và authorization

Dùng test account riêng, không dùng admin production. Route và payload phải lấy từ app contract:

```bash
APP_LOGIN_PATH="${APP_LOGIN_PATH:-/auth/login}"
test -n "${APP_TEST_EMAIL:-}"
test -n "${APP_TEST_PASSWORD:-}"

curl -sS -o /dev/null -w 'login_http=%{http_code}\n' \
  -X POST "${API_BASE_URL}${APP_LOGIN_PATH}" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${APP_TEST_EMAIL}\",\"password\":\"${APP_TEST_PASSWORD}\"}" \
  | tee "$EVIDENCE_DIR/auth-status.txt"
```

Expected: test account login thành công theo contract; request không có credential/token hợp lệ phải trả `401` hoặc `403`; không lưu response body chứa token vào evidence.

### APP-05 — Core business smoke test

Chọn các flow read/write tối thiểu của app, ví dụ:

1. Đăng nhập bằng test account.
2. Đọc một resource public.
3. Thực hiện một flow nghiệp vụ nhỏ trên dữ liệu test.
4. Xác nhận response schema/status.
5. Cleanup dữ liệu test nếu flow có ghi dữ liệu.

Không tự điền endpoint hoặc payload khi app contract chưa cung cấp. Nếu chưa có test suite/API contract, trạng thái là `Blocked`, không phải `Pass`.

Evidence cần giữ: test report, HTTP status/schema assertion và test data ID đã được redact nếu cần.

### APP-06 — Database migration và admin provisioning

- Chạy `./scripts/run-db-migration.sh` một lần; expected exit `0` và SSM command `Success`.
- Chạy `./scripts/provision-admin.sh --env-file environments/dev/admin-provision.env` một lần.
- Xác nhận admin login và quyền tối thiểu đúng expected.
- Không chạy migration từ từng EC2 trong ASG và không đưa secret vào log.

### APP-07 — Frontend functional smoke

Trên CloudFront domain:

- Mở `/` và xác nhận HTML/JS/CSS tải thành công.
- Mở một deep-link client-side rồi refresh trực tiếp.
- Xác nhận frontend gọi đúng `${API_BASE_URL}`.
- Xác nhận browser không báo CORS error.
- Xác nhận API error/unauthorized state hiển thị đúng, không lộ stack trace hoặc secret.

Evidence: browser test report hoặc Playwright/Cypress report nếu app repository có suite.

### APP-08 — Application logs và error handling

- Gửi một request thành công và một request lỗi có chủ ý, không dùng secret thật trong input.
- Xác nhận API log có correlation/request information cần thiết.
- Xác nhận status code/error body đúng contract.
- Xác nhận log không chứa password, `DATABASE_URL`, session secret, token hoặc full authorization header.

## 7. App contract cần bổ sung trước khi sign-off

| Contract | Giá trị cần cung cấp | Nếu thiếu |
|---|---|---|
| Public health route | Ví dụ `/api/health` | APP-02 `Blocked` |
| Readiness/database route | Ví dụ `/api/ready` hoặc read-only DB endpoint | APP-02 `Not applicable`/`Blocked` |
| CORS test route | API route hỗ trợ `OPTIONS` | APP-03 `Blocked` |
| Login route/payload | Path, request schema, expected status | APP-04 `Blocked` |
| Core business flow | Test data, cleanup, expected response schema | APP-05 `Blocked` |
| Browser/API test suite | Playwright/Cypress/Jest/API integration command | APP-07 `Chưa xác minh` |

## 8. Sign-off system và app

Deployment chỉ sign-off khi:

- Tất cả SYS-01 đến SYS-05 đạt `Pass`.
- APP-01 đến APP-04 đạt `Pass` hoặc có trạng thái `Not applicable` được app owner xác nhận.
- Ít nhất một core business flow APP-05 đạt `Pass`.
- Migration/admin provisioning và frontend functional smoke đạt `Pass`.
- Không có secret exposure, unexpected alarm hoặc drift trong post-deploy plan.

Trạng thái runtime hiện tại: `Chưa xác minh` cho tới khi chạy trên AWS account thật.
