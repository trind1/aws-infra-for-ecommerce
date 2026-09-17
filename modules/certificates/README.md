# Certificates module

Module reusable để request và DNS-validate public ACM certificates cho các environment có
domain public. Module hỗ trợ hai certificate độc lập:

```text
ALB origin certificate       → ACM regional certificate
CloudFront viewer certificate → ACM certificate tại us-east-1
```

Environment `dev` hiện không gọi module này. `dev` dùng
[`certificates-imported`](../certificates-imported) với self-signed certificate local cho
ALB và certificate mặc định của CloudFront.

## Khi nào sử dụng

Sử dụng module này khi:

- ALB/CloudFront có hostname public thuộc quyền quản lý của hệ thống.
- Có thể tạo DNS validation CNAME trong Route 53 hoặc DNS provider bên ngoài.
- Cần certificate được public CA tin cậy để browser/CloudFront validate TLS.

Không dùng module này cho hostname local `e-commerce-ndt.test`; hostname đó không có public
DNS validation và không phù hợp với public ACM certificate.

## Resources

| Resource | Vai trò |
|---|---|
| `aws_acm_certificate.alb` | Request certificate regional cho ALB origin |
| `aws_route53_record.alb_validation` | Tùy chọn tạo DNS validation records cho ALB |
| `aws_acm_certificate_validation.alb` | Chờ ACM xác nhận certificate ALB |
| `aws_acm_certificate.cloudfront` | Tùy chọn request viewer certificate tại `us-east-1` |
| `aws_route53_record.cloudfront_validation` | Tùy chọn tạo DNS validation records cho CloudFront |
| `aws_acm_certificate_validation.cloudfront` | Chờ ACM xác nhận viewer certificate |

Module không tạo ALB, CloudFront distribution, alias, Route 53 hosted zone hoặc DNS record
trỏ traffic tới ALB/CloudFront.

## Certificate và region

- Certificate ALB phải nằm trong AWS region nơi ALB được triển khai.
- Certificate CloudFront phải nằm tại `us-east-1`.
- Composition layer phải truyền provider alias `aws.us_east_1` khi sử dụng viewer certificate.
- Certificate domain/SAN phải khớp hostname mà client hoặc origin sử dụng.

## DNS validation

Nếu truyền `alb_route53_zone_id` hoặc `cloudfront_route53_zone_id`, module tự tạo các
CNAME validation records và chờ `aws_acm_certificate_validation` hoàn tất.

Nếu không truyền zone ID, module không tạo DNS record. Khi đó DNS operator phải tạo các
record được xuất qua `*_certificate_validation_records`, sau đó đặt cờ tương ứng:

```hcl
alb_certificate_ready       = true
cloudfront_certificate_ready = true
```

Các cờ `*_certificate_ready` là xác nhận ngoài Terraform rằng ACM certificate đã ở trạng
thái `ISSUED`; chúng không tự thực hiện validation.

## Inputs

| Input | Bắt buộc | Mục đích |
|---|---:|---|
| `project_name` | Có | Prefix tên resource và tag |
| `environment` | Có | Suffix môi trường |
| `alb_origin_domain` | Có | Domain chính của certificate ALB |
| `alb_subject_alternative_names` | Không | SAN bổ sung cho certificate ALB |
| `alb_route53_zone_id` | Không | Hosted zone dùng để tạo ALB validation CNAME |
| `alb_certificate_ready` | Không | Xác nhận certificate ALB external-DNS đã `ISSUED` |
| `enable_custom_viewer_domain` | Không | Bật request certificate cho custom CloudFront domain |
| `cloudfront_viewer_domain` | Khi bật viewer | Domain chính của viewer certificate |
| `cloudfront_subject_alternative_names` | Không | SAN bổ sung cho viewer certificate |
| `cloudfront_route53_zone_id` | Không | Hosted zone dùng để tạo viewer validation CNAME |
| `cloudfront_certificate_ready` | Không | Xác nhận viewer certificate external-DNS đã `ISSUED` |

## Outputs

| Output | Consumer |
|---|---|
| `alb_certificate_arn` | HTTPS listener của ALB |
| `cloudfront_certificate_arn` | Viewer certificate của CloudFront |
| `alb_certificate_validation_records` | DNS operator tạo validation records |
| `cloudfront_certificate_validation_records` | DNS operator tạo viewer validation records |

ARN chỉ được xuất khi certificate đã được validation trong Terraform hoặc cờ `ready`
tương ứng được bật. Private key, DNS token và registrar credential không được module tạo
hoặc output.

## Example

```hcl
module "certificates" {
  source = "../../modules/certificates"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment

  alb_origin_domain   = var.alb_origin_domain
  alb_route53_zone_id = var.alb_route53_zone_id

  enable_custom_viewer_domain = true
  cloudfront_viewer_domain    = var.cloudfront_viewer_domain
  cloudfront_route53_zone_id  = var.cloudfront_route53_zone_id
}
```

## Validation

```bash
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
```
