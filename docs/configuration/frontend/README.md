# Frontend và CloudFront configuration

## Mục tiêu

CloudFront chỉ phục vụ frontend tĩnh:

```text
Browser HTTPS → CloudFront default domain → S3 private + OAC
```

Frontend gọi API trực tiếp bằng:

```text
https://e-commerce-ndt.test/api/...
```

## Contract

| Hạng mục | Giá trị mục tiêu |
|---|---|
| S3 | Private, Block Public Access, versioning, SSE-S3 |
| CloudFront origin | Chỉ S3 |
| OAC | SigV4 signing luôn bật |
| Viewer | HTTPS với default `cloudfront.net` certificate |
| API behavior | Không tạo trong environment `dev` mục tiêu |
| API base URL | `https://e-commerce-ndt.test` |

## Feature flag và migration

Module có `enable_api_origin`. Khi `false`, module không tạo ALB origin hoặc ordered
behavior `/api/*`; khi `true`, module vẫn hỗ trợ contract cũ `CloudFront → ALB HTTP/HTTPS`.
Environment `dev` đặt `enable_cloudfront_api = false` để API đi trực tiếp tới ALB.

## Application requirements

- Frontend build phải dùng API base URL đúng hostname local.
- API phải bật CORS cho origin CloudFront cụ thể.
- Nếu frontend được mở từ một origin khác nhau theo từng environment, CORS phải được
  cấu hình bằng allowlist theo environment.
- Upload frontend build và CloudFront invalidation là pipeline/operation riêng.

## Checklist

| Hạng mục | Trạng thái |
|---|---|
| Private S3 + OAC | Current |
| CloudFront default HTTPS | Current |
| Static cache behavior | Current |
| Disable API origin/behavior khỏi dev | Implemented bằng `enable_cloudfront_api = false`, chưa apply |
| Frontend API base URL | Ngoài Terraform |
| CORS | Ngoài Terraform |
| CloudFront static verification | Chưa xác minh trên AWS |
