# Frontend module

Tạo private S3 bucket, chặn public access, bật versioning và mã hóa SSE-S3. Bucket policy chỉ cho CloudFront service principal đọc object khi `AWS:SourceArn` là distribution này; CloudFront dùng OAC SigV4.

Distribution có hai origin và hai luồng: default behavior phục vụ S3 static build, còn `/api/*` chuyển tới ALB và thêm custom origin header. Viewer HTTP luôn redirect sang HTTPS. Giai đoạn hiện tại người dùng dùng hostname mặc định `https://<distribution>.cloudfront.net` với certificate mặc định do CloudFront cung cấp; custom viewer domain là `Optional / Future improvement`. CloudFront → ALB vẫn có mục tiêu HTTPS độc lập, cần ALB origin domain và certificate regional khớp domain đó; chưa được tự động coi là sẵn sàng khi các quyết định này chưa chốt.

| Input chính | Output chính |
|---|---|
| `alb_origin_dns_name`, `origin_custom_header_*` | `cloudfront_domain_name`, `cloudfront_distribution_id` |
| `cloudfront_aliases`, `cloudfront_certificate_arn` | `bucket_id`, `bucket_arn` |
| `cloudfront_price_class` | `origin_access_control_id` |
