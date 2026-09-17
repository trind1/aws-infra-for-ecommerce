# Certificates module

Module reusable quản lý ACM certificate cho hai kết nối HTTPS độc lập trong các
environment cần HTTPS:

- Certificate regional cho kết nối CloudFront → ALB.
- Certificate viewer tại `us-east-1` cho custom CloudFront domain.

Module không tạo ALB, CloudFront distribution, alias, hosted zone hoặc DNS record ngoài
các record validation khi được truyền Route 53 zone ID. Environment `dev` không gọi module
này; dev dùng certificate self-signed local riêng cho ALB và certificate mặc định của
CloudFront.

## Inputs chính

- `project_name`, `environment`
- `alb_origin_domain`, `alb_subject_alternative_names`
- `alb_route53_zone_id`, `alb_certificate_ready`
- `enable_custom_viewer_domain`, `cloudfront_viewer_domain`
- `cloudfront_subject_alternative_names`, `cloudfront_route53_zone_id`
- `cloudfront_certificate_ready`

## Outputs

- `alb_certificate_arn`
- `cloudfront_certificate_arn`
- `alb_certificate_validation_records`
- `cloudfront_certificate_validation_records`

Certificate chỉ được nối tới consumer sau khi ACM validation/ready condition được xác
nhận. Không đưa private key hoặc thông tin DNS nhạy cảm vào state, tag hay output.
