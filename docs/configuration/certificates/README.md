# Kế hoạch cấu hình: certificates

> Tài liệu này mô tả thiết kế và implementation contract; không xác nhận hạ tầng đã được `apply`.

## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 6
- Validated: 0
- Blocked: 1
- Not in scope: 1

## Mục tiêu

Quản lý hai certificate độc lập cho hai kết nối HTTPS trong kiến trúc:

1. **Client → CloudFront:** giai đoạn hiện tại dùng URL mặc định `https://<distribution>.cloudfront.net` và certificate mặc định do CloudFront cung cấp. Luồng này không cần custom viewer domain, Route 53 hosted zone hoặc ACM certificate `us-east-1`.
2. **CloudFront → ALB:** mục tiêu thiết kế hiện tại là HTTPS. ALB cần certificate ACM regional hợp lệ và khớp với hostname mà CloudFront dùng làm ALB origin.

Custom viewer domain cho người dùng là `Optional / Future improvement`; không được dùng một cờ custom viewer domain để tắt certificate bắt buộc của ALB origin.

## Thiết kế hiện tại: certificate cho ALB origin HTTPS

### Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| AWS Certificate Manager cho ALB | Certificate regional tại region triển khai ALB; SAN/domain phải khớp chính xác ALB origin domain mà CloudFront sử dụng. |
| DNS provider | Dùng để cấp DNS validation cho certificate ALB; có thể là Route 53 hoặc DNS provider bên ngoài. Hosted zone và cách quản lý DNS hiện chưa được chốt. |
| CloudFront origin | Kết nối tới ALB bằng HTTPS sau khi certificate hợp lệ và CloudFront origin protocol được cấu hình `https-only`. |
| CloudFront viewer | Dùng certificate mặc định của CloudFront cho hostname `*.cloudfront.net`; không tạo certificate riêng trong giai đoạn này. |

### Input contract

- `alb_origin_domain`: bắt buộc; hostname CloudFront sẽ dùng để kết nối ALB bằng HTTPS.
- `alb_subject_alternative_names`: SAN tùy chọn cho certificate regional.
- `alb_route53_zone_id`: tùy chọn nếu muốn module tạo CNAME validation trong Route 53.
- `alb_certificate_ready`: xác nhận thủ công certificate đã `ISSUED` khi DNS được quản lý bên ngoài Terraform.
- Provider mặc định của module phải trỏ tới region triển khai ALB.

### Output contract

- ACM ARN regional cho ALB, chỉ được dùng khi certificate hợp lệ và khớp ALB origin domain.
- `alb_certificate_validation_records` để DNS operator xử lý nếu không dùng Route 53.
- Không xuất CloudFront viewer certificate ở giai đoạn dùng hostname mặc định.

### Điều kiện chấp nhận

- Certificate ALB ở đúng region triển khai và khớp hostname CloudFront dùng để kết nối origin.
- CloudFront → ALB giữ mục tiêu HTTPS; không chuyển sang HTTP chỉ vì viewer domain đang dùng hostname mặc định.
- Không giả định có thể cấp certificate cho DNS mặc định `*.elb.amazonaws.com`; origin domain, DNS và phương án certificate còn mở là blocker.
- Client → CloudFront dùng certificate mặc định do CloudFront cung cấp, độc lập với certificate regional của ALB.
- Không đưa private key, token DNS hoặc thông tin registrar vào state/tài liệu.

## Optional / Future improvement: custom viewer domain

### Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| CloudFront alias | Thêm custom viewer domain vào distribution khi tính năng được phê duyệt. |
| AWS Certificate Manager cho CloudFront | Certificate viewer domain tại `us-east-1`, có domain/SAN khớp alias. |
| DNS provider | Tạo record trỏ custom viewer domain tới CloudFront và record DNS validation; Route 53 chỉ là một lựa chọn. |
| Feature flag | Nếu cần flag, dùng tên thể hiện rõ `enable_custom_viewer_domain`; flag này chỉ điều khiển alias/viewer certificate, không điều khiển ALB certificate. |

### Input và output tương lai

- Input: `enable_custom_viewer_domain`, `cloudfront_viewer_domain`, `cloudfront_subject_alternative_names`, `cloudfront_route53_zone_id` và `cloudfront_certificate_ready`.
- Output: `cloudfront_certificate_arn` tại `us-east-1` và `cloudfront_certificate_validation_records`.
- Alias CloudFront và DNS record trỏ custom viewer domain do composition/frontend quản lý.
- Certificate regional của ALB vẫn tồn tại và phục vụ CloudFront → ALB; không bị thay thế bởi viewer certificate.

### Điều kiện chấp nhận tương lai

- Chỉ bật alias sau khi certificate `us-east-1` đã hợp lệ.
- Custom viewer domain không làm thay đổi ALB origin domain hoặc certificate regional.
- Người dùng vẫn có thể truy cập bằng hostname mặc định nếu alias chưa được bật.

## Implementation checklist

| # | Hạng mục | Trạng thái | Evidence code | Evidence validation | Consumer / ghi chú |
|---:|---|---|---|---|---|
| 1 | Thiết kế tách viewer certificate và ALB origin certificate | Implemented | `docs/configuration/certificates/README.md:16` | Đối chiếu thiết kế — Pass | Hai kết nối HTTPS độc lập |
| 2 | Input regional ALB certificate | Implemented | `modules/certificates/variables.tf:11` | `terraform fmt -check modules/certificates environments/dev/main.tf environments/dev/providers.tf environments/dev/variables.tf environments/dev/outputs.tf` — exit 0 | `alb_origin_domain` là required input |
| 3 | Resource ACM regional và DNS validation ALB | Implemented | `modules/certificates/main.tf:7` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Chưa thể xác nhận toàn bộ composition |
| 4 | Input và resource custom viewer certificate `us-east-1` | Implemented | `modules/certificates/variables.tf:36`, `modules/certificates/main.tf:48` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Chỉ khi `enable_custom_viewer_domain = true` |
| 5 | Output ARN và validation records | Implemented | `modules/certificates/outputs.tf:1` | `terraform fmt -check modules/certificates environments/dev/main.tf environments/dev/providers.tf environments/dev/variables.tf environments/dev/outputs.tf` — exit 0 | Không coi request ARN là ARN đã `ISSUED` |
| 6 | Environment provider alias và module wiring | Implemented | `environments/dev/providers.tf:14`, `environments/dev/main.tf:46` | `terraform -chdir=environments/dev validate` — Blocked bởi required arguments còn thiếu ở `module.compute` | Đã truyền `aws.us_east_1` |
| 7 | HTTPS CloudFront → ALB sẵn sàng | Blocked | `docs/configuration/certificates/README.md:48` | Chưa có origin domain/DNS/certificate có thể kiểm chứng | Không báo PASS; cần quyết định authoritative origin domain |
| 8 | Custom viewer alias và DNS record | Not in scope | `docs/configuration/certificates/README.md:56` | Chưa xác minh | Optional / Future improvement; thuộc frontend/composition |
