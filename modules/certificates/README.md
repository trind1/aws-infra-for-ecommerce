# Certificates module

Module reusable quản lý ACM certificate cho hai kết nối HTTPS độc lập trong các environment cần HTTPS:

- **CloudFront → ALB:** certificate regional của ALB được tạo ở region triển khai ALB và phải khớp chính xác hostname mà CloudFront dùng làm origin.
- **Client → CloudFront:** giai đoạn hiện tại dùng URL mặc định `https://<distribution>.cloudfront.net` và certificate mặc định do CloudFront cung cấp. Certificate ACM tại `us-east-1` chỉ thuộc `Optional / Future improvement` cho custom viewer domain.

Module không tạo ALB, CloudFront distribution, alias CloudFront, Route 53 hosted zone hoặc DNS record trỏ viewer domain. Không giả định certificate có thể cấp cho DNS mặc định `*.elb.amazonaws.com`.

Environment `dev` hiện dùng HTTP origin và không gọi module này; module chỉ là building block cho environment production/HTTPS trong tương lai.

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 8
- Validated: 1
- Blocked: 1
- Not in scope: 1

## Hành vi theo giai đoạn

| Trường hợp | ALB regional certificate | CloudFront viewer certificate |
|---|---|---|
| Hiện tại, `enable_custom_viewer_domain = false` | Luôn request certificate cho `alb_origin_domain`; Route 53 validation là tùy chọn | Không tạo; CloudFront dùng certificate mặc định cho `*.cloudfront.net` |
| Tương lai, `enable_custom_viewer_domain = true` | Vẫn giữ nguyên, không phụ thuộc cờ viewer domain | Tạo tại `us-east-1` cho `cloudfront_viewer_domain` |

`alb_certificate_ready` và `cloudfront_certificate_ready` chỉ dùng để xác nhận certificate đã `ISSUED` khi DNS validation được quản lý bên ngoài Terraform. Khi truyền Route 53 zone tương ứng, `aws_acm_certificate_validation` là bằng chứng validation trong Terraform và ARN được xuất sau resource đó hoàn tất.

## Inputs

| Input | Bắt buộc | Ý nghĩa |
|---|---:|---|
| `project_name` | Có | Prefix ổn định cho tên resource |
| `environment` | Có | Hậu tố môi trường trong tên resource |
| `alb_origin_domain` | Có | Hostname CloudFront dùng để kết nối ALB bằng HTTPS; phải khớp certificate regional |
| `alb_subject_alternative_names` | Không | SAN của certificate ALB, mặc định `[]` |
| `alb_route53_zone_id` | Không | Hosted zone public Route 53 để tự tạo CNAME validation cho certificate ALB |
| `alb_certificate_ready` | Không | Xác nhận thủ công certificate ALB external DNS đã `ISSUED`, mặc định `false` |
| `enable_custom_viewer_domain` | Không | Chỉ bật certificate viewer tương lai, mặc định `false` |
| `cloudfront_viewer_domain` | Khi bật viewer domain | Custom hostname người dùng dùng để vào CloudFront |
| `cloudfront_subject_alternative_names` | Không | SAN của certificate viewer, mặc định `[]` |
| `cloudfront_route53_zone_id` | Không | Hosted zone public Route 53 để tự tạo CNAME validation cho certificate viewer |
| `cloudfront_certificate_ready` | Không | Xác nhận thủ công certificate viewer external DNS đã `ISSUED`, mặc định `false` |

## DNS validation

Nếu có `alb_route53_zone_id` hoặc `cloudfront_route53_zone_id`, module tạo các CNAME validation tương ứng và chờ ACM validation. Nếu không có zone ID, module xuất validation records để DNS operator tạo ở provider bên ngoài. Zone phải thực sự authoritative cho domain; module không tự tạo hosted zone và không tự xác nhận ownership.

Không đưa private key, token DNS hoặc thông tin registrar vào variable, state, tag hay output. ARN certificate không phải private key nhưng chỉ được nối vào ALB/CloudFront sau khi điều kiện `ISSUED` đã được kiểm chứng.

## Outputs

| Output | Consumer / mục đích |
|---|---|
| `alb_certificate_arn` | ALB HTTPS listener cho CloudFront origin; `null` khi external validation chưa được xác nhận |
| `cloudfront_certificate_arn` | CloudFront viewer certificate tại `us-east-1`; `null` khi feature tắt hoặc certificate chưa sẵn sàng |
| `alb_certificate_validation_records` | DNS provider/operator dùng để validate certificate regional |
| `cloudfront_certificate_validation_records` | DNS provider/operator dùng để validate certificate viewer tương lai |

## Ví dụ composition

```hcl
module "certificates" {
  source = "../../modules/certificates"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment

  alb_origin_domain     = var.alb_origin_domain
  alb_route53_zone_id   = var.alb_route53_zone_id
  alb_certificate_ready = var.alb_certificate_ready

  enable_custom_viewer_domain = var.enable_custom_viewer_domain
  cloudfront_viewer_domain    = var.cloudfront_viewer_domain
}
```

`aws.us_east_1` phải được khai báo ở composition layer dù custom viewer domain đang tắt, vì module có resource dùng provider alias theo điều kiện.

## Implementation checklist

| # | Hạng mục | Trạng thái | Evidence code | Evidence validation | Consumer / ghi chú |
|---:|---|---|---|---|---|
| 1 | Boundary và non-goals | Implemented | `modules/certificates/README.md:8` | Chưa xác minh | Không tạo ALB, CloudFront distribution hoặc hosted zone |
| 2 | Input contract hai certificate độc lập | Implemented | `modules/certificates/variables.tf:1` | `terraform fmt -check modules/certificates environments/dev/main.tf environments/dev/providers.tf environments/dev/variables.tf environments/dev/outputs.tf` — exit 0 | Không còn cờ dùng chung để tắt certificate ALB |
| 3 | ACM regional certificate cho ALB | Implemented | `modules/certificates/main.tf:7` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Consumer tương lai: ALB HTTPS listener |
| 4 | Route 53 validation cho ALB, optional | Implemented | `modules/certificates/main.tf:25` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Zone ID phải authoritative |
| 5 | ACM viewer certificate tại `us-east-1`, optional/future | Implemented | `modules/certificates/main.tf:48` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Chỉ tạo khi `enable_custom_viewer_domain = true` |
| 6 | Route 53 validation cho viewer certificate | Implemented | `modules/certificates/main.tf:69` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Không thay thế certificate regional ALB |
| 7 | Output ARN và validation records | Implemented | `modules/certificates/outputs.tf:1` | `terraform fmt -check modules/certificates environments/dev/main.tf environments/dev/providers.tf environments/dev/variables.tf environments/dev/outputs.tf` — exit 0 | ARN bị gate theo validation/readiness |
| 8 | Provider alias và environment wiring | Implemented | `environments/dev/providers.tf:14`, `environments/dev/main.tf:46` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Alias `aws.us_east_1` đã truyền vào module |
| 9 | HCL formatting | Validated | `modules/certificates/main.tf:1`, `environments/dev/main.tf:46` | `terraform fmt -check modules/certificates environments/dev/main.tf environments/dev/providers.tf environments/dev/variables.tf environments/dev/outputs.tf` — exit 0 | Chỉ trong scope thay đổi |
| 10 | Root composition validation | Blocked | `environments/dev/main.tf:108` | `terraform -chdir=environments/dev validate` — thiếu required arguments của `module.compute` | Cần hoàn thiện wiring compute rồi chạy lại |
| 11 | CloudFront alias và DNS viewer record | Not in scope | `docs/configuration/certificates/README.md:56` | Chưa xác minh | Thuộc triển khai custom viewer domain tương lai/frontend |
