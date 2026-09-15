# Module: Frontend

Module này tạo nơi lưu frontend tĩnh trong S3 private và phân phối qua một CloudFront distribution. Distribution có hai origin: S3 cho static assets và ALB cho API `/api/*`.

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 8
- Validated: 0
- Blocked: 1
- Not in scope: 1

Ở giai đoạn hiện tại, viewer dùng hostname mặc định `https://<distribution>.cloudfront.net` và certificate mặc định do CloudFront cung cấp. Custom viewer domain là `Optional / Future improvement`; module chỉ dùng alias và certificate `us-east-1` khi cả hai được truyền rõ ràng.

## Sơ đồ và phạm vi

```text
Client
  │ HTTPS tới *.cloudfront.net
  │ certificate mặc định của CloudFront
  ▼
CloudFront distribution
  ├── default behavior ──► S3 private bucket
  │                         OAC SigV4
  │
  └── /api/* ── HTTPS + X-Origin-Verify ──► ALB origin hostname
                                            │
                                            ▼
                                     API target group
```

Module quản lý S3 bucket, các bucket security controls, OAC, CloudFront distribution và bucket policy. ALB, ACM certificate, Route 53 hosted zone/record và việc upload artifact không thuộc module này.

## Resources và data sources

| Resource/data source | Số lượng | Cấu hình chính |
|---|---:|---|
| `aws_s3_bucket.frontend` | 1 | Bucket prefix duy nhất, `force_destroy` do environment quyết định. |
| `aws_s3_bucket_public_access_block.frontend` | 1 | Chặn public ACL, public policy và public bucket. |
| `aws_s3_bucket_ownership_controls.frontend` | 1 | `BucketOwnerEnforced`, không phụ thuộc ACL. |
| `aws_s3_bucket_versioning.frontend` | 1 | Bật versioning cho artifact rollback/audit. |
| `aws_s3_bucket_server_side_encryption_configuration.frontend` | 1 | SSE-S3 (`AES256`) mặc định. |
| `aws_cloudfront_origin_access_control.frontend` | 1 | SigV4, signing `always`, origin type S3. |
| `aws_cloudfront_distribution.this` | 1 | S3 default origin, ALB API origin, default viewer certificate hoặc custom certificate theo input. |
| `aws_iam_policy_document.frontend_bucket` | 1 | Chỉ CloudFront service principal của distribution này được `s3:GetObject`. |
| `aws_s3_bucket_policy.frontend` | 1 | Gắn policy OAC vào bucket. |
| CloudFront managed policy data sources | 3 | Cache optimized cho S3, caching disabled cho API và viewer request policy không forward Host header. |

## Luồng và hành vi

### S3 static origin

- Bucket không public, không cấu hình S3 website endpoint.
- CloudFront truy cập bucket bằng OAC SigV4.
- Bucket policy giới hạn `AWS:SourceArn` đúng distribution ARN.
- Default behavior dùng managed `Managed-CachingOptimized`, cho phép `GET`, `HEAD`, `OPTIONS` và redirect viewer HTTP sang HTTPS.

### ALB API origin

- Ordered behavior chỉ match `/api/*`.
- CloudFront kết nối ALB bằng `https-only` và chỉ dùng TLSv1.2.
- CloudFront gửi custom header `X-Origin-Verify` cùng secret value; ALB listener kiểm tra lại header này.
- API dùng `Managed-CachingDisabled` và cho phép các HTTP methods cần cho API; Host header mặc định không forward nguyên trạng.
- `alb_origin_dns_name` phải là hostname mà certificate regional của ALB bao phủ. Không tự dùng DNS mặc định `*.elb.amazonaws.com` làm certificate hostname.

### Viewer domain và certificate

- Khi `cloudfront_aliases = []` và `cloudfront_certificate_arn = null`, CloudFront dùng hostname mặc định và certificate mặc định.
- Khi truyền custom aliases, module yêu cầu certificate ARN tương ứng; certificate phải được cấp ở `us-east-1`.
- Module không tạo ACM certificate, DNS validation record, hosted zone hoặc alias DNS record.

## Inputs

| Name | Type | Required | Default | Mục đích |
|---|---|---:|---|---|
| `project_name` | `string` | Yes | - | Prefix tên resource. |
| `environment` | `string` | Yes | - | Tên môi trường. |
| `alb_origin_dns_name` | `string` | Yes | - | Hostname CloudFront dùng để kết nối ALB bằng HTTPS. |
| `alb_origin_protocol_policy` | `string` | Yes | - | Hiện tại bắt buộc `https-only`. |
| `cloudfront_aliases` | `list(string)` | No | `[]` | Custom viewer aliases; để rỗng cho hostname mặc định. |
| `cloudfront_certificate_arn` | `string` | No | `null` | ACM certificate `us-east-1` cho custom viewer domain. |
| `cloudfront_price_class` | `string` | No | `PriceClass_100` | Price class của distribution. |
| `origin_custom_header_name` | `string` | No | `X-Origin-Verify` | Header CloudFront gửi tới ALB. |
| `origin_custom_header_value` | `string` | Yes | - | Secret value dùng chung với ALB. |
| `bucket_force_destroy` | `bool` | No | `false` | Cho phép xóa object khi destroy bucket. |

Module không nhận `tags`. Provider environment áp dụng `Project`, `Environment`, `ManagedBy`; module thêm `Name`, `Component` và `Tier` cho resource taggable.

## Outputs

| Output | Consumer | Ý nghĩa |
|---|---|---|
| `bucket_id` | Upload pipeline/environment | Tên S3 bucket frontend. |
| `bucket_arn` | Audit/policy tooling | ARN bucket frontend. |
| `cloudfront_distribution_id` | Deploy/invalidation pipeline | ID distribution. |
| `cloudfront_distribution_arn` | Audit/IAM | ARN distribution. |
| `cloudfront_domain_name` | Người dùng/vận hành | Hostname mặc định do CloudFront cấp; custom alias là cấu hình riêng. |
| `origin_access_control_id` | Audit/vận hành | ID OAC gắn với S3 origin. |

## Dependencies

```text
certificates ─────────► cloudfront_certificate_arn (optional/future)
ALB ──────────────────► ALB origin hostname contract
environment variables ─► header, protocol, price class, force_destroy
                              │
                              ▼
                           frontend
                              ├──► CloudFront default domain
                              └──► private S3 bucket
```

Environment hiện truyền `var.alb_origin_domain` làm origin hostname của CloudFront. DNS authoritative trỏ hostname đó về ALB và certificate regional khớp hostname vẫn là quyết định mở; module không tự tạo DNS để che blocker này.

## Checklist và evidence

| Hạng mục | Trạng thái | Evidence | Validation |
|---|---|---|---|
| Private S3 bucket với public access block | Implemented | `main.tf:24`, `main.tf:37` | `terraform fmt -check` — Pass; composition validate bị database block |
| Ownership enforced, versioning và SSE-S3 | Implemented | `main.tf:48`, `main.tf:58`, `main.tf:68` | `terraform fmt -check` — Pass; composition validate bị database block |
| OAC SigV4 và bucket policy giới hạn SourceArn | Implemented | `main.tf:80`, `main.tf:173` | `terraform fmt -check` — Pass; composition validate bị database block |
| CloudFront S3 default behavior | Implemented | `main.tf:90`, `main.tf:121` | `terraform fmt -check` — Pass; composition validate bị database block |
| CloudFront `/api/*` tới ALB bằng HTTPS và custom header | Implemented | `main.tf:103`, `main.tf:107`, `main.tf:131` | `terraform fmt -check` — Pass; composition validate bị database block |
| Default viewer domain/certificate hiện tại | Implemented | `main.tf:148`, `main.tf:150` | `terraform fmt -check` — Pass; composition validate bị database block |
| Custom viewer domain có guard alias/certificate | Implemented | `variables.tf:26`, `main.tf:161` | `terraform fmt -check` — Pass; composition validate bị database block |
| Outputs và environment wiring | Implemented | `outputs.tf:1`, `environments/dev/main.tf:98`, `environments/dev/outputs.tf:81` | `terraform fmt -check` — Pass; composition validate bị database block |
| Origin DNS/certificate HTTPS đã sẵn sàng trên AWS | Blocked | Origin hostname, DNS và certificate regional chưa có evidence | Chưa xác minh; chưa chạy apply |
| Route 53 hosted zone/alias cho viewer domain | Not in scope | DNS và alias record không do module tạo; custom viewer domain là future | Chưa xác minh |

## Kiểm tra

```bash
terraform -chdir=environments/dev fmt -check -recursive
terraform -chdir=environments/dev validate
```

Các lệnh trên chỉ kiểm tra format/schema; không xác nhận CloudFront distribution, S3 bucket, DNS hay ACM certificate đã tồn tại. Không chạy `terraform apply` hoặc `terraform destroy` trong review module.
