# Frontend module

Module tạo S3 bucket private, Origin Access Control và CloudFront distribution cho
frontend tĩnh. Kiến trúc mục tiêu không dùng CloudFront làm API entry point.

## Resources

| Resource | Vai trò |
|---|---|
| `aws_s3_bucket.frontend` | Lưu frontend build |
| Public access block/ownership/versioning/encryption | Bảo vệ bucket và rollback artifact |
| `aws_cloudfront_origin_access_control.frontend` | SigV4 access từ CloudFront tới S3 |
| `aws_cloudfront_distribution.this` | HTTPS viewer và static caching |
| Bucket policy | Chỉ CloudFront distribution được đọc |

## Mục tiêu sử dụng

```text
Browser → https://<distribution>.cloudfront.net/ → CloudFront → S3 private
```

## Drift cần xử lý

Module có feature flag `enable_api_origin`. Khi `false`, module chỉ tạo S3 origin và
không tạo ordered behavior `/api/*`; khi `true`, module hỗ trợ contract cũ `CloudFront → ALB
HTTP/HTTPS`. Đây là điểm cần xem xét nếu environment production cần API qua CloudFront.

## Inputs/outputs chính

- Identity: `project_name`, `environment`.
- Optional API origin: `enable_api_origin`, `alb_origin_dns_name`, `alb_origin_protocol_policy`.
- Viewer: `cloudfront_aliases`, `cloudfront_certificate_arn`, `cloudfront_price_class`.
- S3: `bucket_force_destroy`.
- Custom header legacy: `origin_custom_header_name`, `origin_custom_header_value`.

Custom viewer domain và ACM certificate `us-east-1` không thuộc module. Dev dùng default
CloudFront domain nên không cần custom domain.

## Trạng thái

| Hạng mục | Trạng thái |
|---|---|
| Private S3 + OAC + static CloudFront | Current |
| Default CloudFront HTTPS | Current |
| Disable ALB origin/API behavior khỏi dev | Implemented bằng feature flag, chưa apply |
| Frontend upload/invalidation | Not in scope |
| CORS/API base URL | Application responsibility |
