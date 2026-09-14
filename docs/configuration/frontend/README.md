# Kế hoạch cấu hình: frontend

## Mục tiêu

Phân phối frontend tĩnh qua CloudFront trong khi giữ S3 private; định tuyến `/api/*` từ hostname mặc định `*.cloudfront.net` tới ALB origin. Custom viewer domain là `Optional / Future improvement`.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| Amazon S3 | Một bucket frontend private; block toàn bộ public access, bucket-owner enforced, versioning và server-side encryption. |
| CloudFront Origin Access Control | OAC dùng để CloudFront truy cập S3; bucket policy chỉ tin cậy distribution dự kiến. |
| CloudFront distribution | Default behavior cho S3 frontend; API behavior `/api/*` tới ALB bằng HTTPS theo mục tiêu origin hiện tại, với cache tắt hoặc phù hợp API. |
| CloudFront viewer hiện tại | Dùng hostname mặc định `https://<distribution>.cloudfront.net` và certificate mặc định do CloudFront cung cấp. |
| ALB origin | CloudFront kết nối bằng HTTPS tới ALB origin domain; custom origin header vẫn là lớp xác thực bổ sung. Origin domain, DNS và certificate regional phải được chốt riêng. |
| Custom viewer domain | `Optional / Future improvement`: chỉ khi bật mới cần alias, DNS và viewer certificate `us-east-1`. |

## Input cần quyết định

- Tên bucket có tính duy nhất toàn cục và chính sách `force_destroy`.
- ALB origin domain/hostname, origin protocol `https-only`, ALB regional certificate và phương án DNS/validation.
- Price class ở giai đoạn hiện tại; aliases và CloudFront ACM ARN `us-east-1` chỉ là input tương lai khi bật custom viewer domain.
- Cache policy, origin request policy và response headers policy theo yêu cầu frontend/API.

## Output contract

- S3 bucket ID/ARN cho upload frontend và policy audit.
- CloudFront distribution ID/ARN và hostname mặc định `*.cloudfront.net` cho vận hành; custom viewer alias là output tương lai.
- OAC ID cho kiểm tra bucket access.

## Điều kiện chấp nhận

- S3 không public và website endpoint S3 không được dùng làm origin public.
- CloudFront có quyền đọc bucket qua OAC, không qua ACL public.
- Giai đoạn hiện tại người dùng truy cập bằng `*.cloudfront.net`, không yêu cầu Route 53 hosted zone, alias hoặc viewer certificate riêng.
- `/api/*` kết nối tới ALB bằng HTTPS theo mục tiêu thiết kế; certificate regional phải hợp lệ và khớp ALB origin domain. Origin domain/DNS/certificate chưa chốt là blocker, không được báo HTTPS origin đã sẵn sàng.
- Custom viewer domain chỉ là cải tiến tương lai; khi bật cần DNS, alias và certificate `us-east-1`, nhưng không thay thế certificate regional của ALB.
