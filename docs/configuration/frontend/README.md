# Kế hoạch cấu hình: frontend

Tài liệu này mô tả contract triển khai frontend và evidence trong repository. Nó không khẳng định S3, CloudFront, DNS hoặc ACM certificate đã được tạo trên AWS.

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 8
- Validated: 0
- Blocked: 1
- Not in scope: 1

## Mục tiêu

Phân phối frontend tĩnh qua CloudFront trong khi giữ S3 private; định tuyến `/api/*` tới ALB origin bằng HTTPS. Giai đoạn hiện tại người dùng dùng hostname mặc định `https://<distribution>.cloudfront.net` và certificate mặc định do CloudFront cung cấp. Custom viewer domain là `Optional / Future improvement`.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| Amazon S3 | Một bucket private; block toàn bộ public access, bucket-owner enforced, versioning và SSE-S3. Không dùng S3 website endpoint public. |
| CloudFront Origin Access Control | OAC SigV4 với signing behavior `always`; bucket policy chỉ cho distribution ARN đọc object. |
| CloudFront S3 origin | Origin dùng regional bucket domain name và OAC; default behavior dùng managed caching optimized. |
| CloudFront ALB origin | Custom origin dùng hostname `alb_origin_domain`, protocol `https-only`, TLSv1.2 và custom origin header. Certificate regional của ALB phải khớp hostname này. |
| CloudFront API behavior | Ordered behavior `/api/*`, caching disabled, forward các method API và không forward Host header viewer nguyên trạng. |
| CloudFront viewer hiện tại | Hostname mặc định `https://<distribution>.cloudfront.net`, viewer HTTP redirect sang HTTPS, certificate mặc định của CloudFront. |
| Custom viewer domain | `Optional / Future improvement`: chỉ khi bật mới dùng alias, DNS và certificate `us-east-1`; không thay thế certificate regional của ALB. |

## Sơ đồ luồng

```text
Client
  │ HTTPS tới https://<distribution>.cloudfront.net
  │ certificate mặc định của CloudFront
  ▼
CloudFront
  ├── default behavior ──OAC SigV4──► S3 private bucket
  │
  └── /api/* ── HTTPS + X-Origin-Verify ──► ALB origin hostname
                                            │ HTTP nội bộ tới target group
                                            ▼
                                           EC2
```

Hai certificate là độc lập: certificate mặc định của CloudFront phục vụ Client → CloudFront; certificate regional phục vụ CloudFront → ALB. Custom viewer domain không thay đổi certificate hoặc protocol của ALB origin.

## Input contract ở environment

| Input module frontend | Nguồn tại environment | Ghi chú |
|---|---|---|
| `alb_origin_dns_name` | `var.alb_origin_domain` | Hostname CloudFront dùng để verify TLS tới ALB; không mặc định bằng DNS `*.elb.amazonaws.com`. |
| `alb_origin_protocol_policy` | `var.cloudfront_alb_origin_protocol_policy` | Hiện bắt buộc `https-only`. |
| `cloudfront_aliases` | `var.enable_custom_viewer_domain ? [coalesce(var.cloudfront_viewer_domain, "")] : []` | Rỗng ở giai đoạn hiện tại. |
| `cloudfront_certificate_arn` | `module.certificates.cloudfront_certificate_arn` | Chỉ có khi custom viewer certificate `us-east-1` được bật và sẵn sàng. |
| `cloudfront_price_class` | `var.cloudfront_price_class` | Mặc định `PriceClass_100`. |
| `origin_custom_header_name/value` | `var.cloudfront_alb_header_name/value` | Phải đồng nhất với ALB listener rule; value là secret. |
| `bucket_force_destroy` | `var.frontend_bucket_force_destroy` | Mặc định `false` để tránh xóa artifact ngoài ý muốn. |

## Domain, certificate và Route 53

### Giai đoạn hiện tại

- Viewer dùng `https://<distribution>.cloudfront.net`; CloudFront tự cung cấp certificate mặc định.
- Không cần domain riêng, Route 53 hosted zone, CloudFront alias hoặc ACM certificate `us-east-1` cho viewer URL mặc định.
- CloudFront → ALB vẫn dùng HTTPS. Certificate regional của ALB phải hợp lệ và khớp ALB origin hostname.
- Repository chưa chốt authoritative DNS và cách trỏ ALB origin hostname về ALB. Không giả định certificate có thể cấp cho DNS mặc định `*.elb.amazonaws.com`; đây là blocker cho việc khẳng định origin HTTPS đã sẵn sàng.

### Optional / Future improvement: custom viewer domain

- Khi bật mới cần custom viewer domain, DNS record trỏ tới CloudFront, alias trong distribution và certificate ACM ở `us-east-1`.
- Certificate viewer `us-east-1` không thay thế certificate regional của ALB.
- Module frontend không tạo hosted zone, DNS record hoặc ACM certificate; các bước đó thuộc composition/DNS/certificates workflow.
- Alias và viewer certificate phải được truyền cùng nhau; module có guard để không tạo custom alias khi certificate chưa sẵn sàng.

## Security và non-goals

- S3 không có public read; bucket policy chỉ cho CloudFront service principal với `AWS:SourceArn` của distribution.
- S3 encryption at rest dùng SSE-S3; OAC bảo vệ kết nối CloudFront → S3.
- API origin dùng HTTPS; custom header là lớp xác thực bổ sung, không thay thế ALB security group.
- Secret header là sensitive input nhưng vẫn có thể xuất hiện trong Terraform state; state/backend phải được bảo vệ.
- Không tạo WAF, Route 53 hosted zone/record, ACM certificate, S3 upload job hoặc invalidation workflow trong module này.

## Output contract

| Output | Consumer | Mục đích |
|---|---|---|
| `bucket_id`, `bucket_arn` | Upload pipeline, audit | Nhận diện bucket và kiểm tra policy. |
| `cloudfront_distribution_id` | Deploy/invalidation pipeline | ID distribution. |
| `cloudfront_distribution_arn` | Audit/IAM | ARN distribution. |
| `cloudfront_domain_name` | Người dùng/vận hành | Hostname mặc định `*.cloudfront.net`. |
| `origin_access_control_id` | Audit/vận hành | ID OAC của S3 origin. |

## Checklist triển khai và evidence

| # | Hạng mục | Trạng thái | Evidence code | Evidence validation | Consumer/ghi chú |
|---:|---|---|---|---|---|
| 1 | Private S3 bucket và public access controls | Implemented | `modules/frontend/main.tf:24`, `modules/frontend/main.tf:37` | `terraform fmt -check` — Pass; composition validate bị database block | S3 static origin |
| 2 | Ownership, versioning và encryption | Implemented | `modules/frontend/main.tf:48`, `modules/frontend/main.tf:58`, `modules/frontend/main.tf:68` | `terraform fmt -check` — Pass; composition validate bị database block | SSE-S3; artifact rollback |
| 3 | OAC SigV4 và bucket policy SourceArn | Implemented | `modules/frontend/main.tf:80`, `modules/frontend/main.tf:173` | `terraform fmt -check` — Pass; composition validate bị database block | Chỉ distribution được đọc object |
| 4 | CloudFront S3 default behavior | Implemented | `modules/frontend/main.tf:90`, `modules/frontend/main.tf:121` | `terraform fmt -check` — Pass; composition validate bị database block | Managed-CachingOptimized |
| 5 | CloudFront `/api/*` HTTPS tới ALB | Implemented | `modules/frontend/main.tf:103`, `modules/frontend/main.tf:107`, `modules/frontend/main.tf:131` | `terraform fmt -check` — Pass; composition validate bị database block | ALB origin domain/certificate là dependency |
| 6 | Default viewer domain/certificate | Implemented | `modules/frontend/main.tf:148`, `modules/frontend/main.tf:150` | `terraform fmt -check` — Pass; composition validate bị database block | `*.cloudfront.net`, không cần Route 53 |
| 7 | Optional viewer alias/certificate guard | Implemented | `modules/frontend/variables.tf:26`, `modules/frontend/main.tf:161` | `terraform fmt -check` — Pass; composition validate bị database block | Chỉ bật trong tương lai |
| 8 | Output và environment wiring | Implemented | `modules/frontend/outputs.tf:1`, `environments/dev/main.tf:98`, `environments/dev/outputs.tf:81` | `terraform fmt -check` — Pass; composition validate bị database block | Frontend outputs dùng cho vận hành |
| 9 | ALB origin DNS/certificate HTTPS đã sẵn sàng | Blocked | `docs/configuration/certificates/README.md:52` | Chưa xác minh | Không báo PASS khi chưa chốt hostname/DNS/certificate |
| 10 | Route 53 hosted zone/alias | Not in scope | `modules/frontend/README.md:24` | Chưa xác minh | DNS thuộc workflow khác |

## Kiểm tra đề xuất

```bash
terraform -chdir=environments/dev fmt -check -recursive
terraform -chdir=environments/dev validate
```

Format/validate không chứng minh DNS resolution, ACM status, CloudFront deployment hoặc TLS handshake tới ALB. Không chạy `terraform apply` hoặc `terraform destroy` trong bước review này.
