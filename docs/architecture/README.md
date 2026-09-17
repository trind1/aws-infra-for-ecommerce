# Kiến trúc mục tiêu

Tài liệu này ghi nhận quyết định cho môi trường `dev` trước khi chỉnh Terraform.
Kiến trúc được chọn là **frontend qua CloudFront, API truy cập trực tiếp ALB HTTPS**.

## Luồng người dùng

```text
User / Browser
├── HTTPS https://<distribution>.cloudfront.net/
│       └── CloudFront
│              └── S3 private + OAC
│
└── HTTPS https://e-commerce-ndt.test/api/...
        └── ALB :443
               └── EC2 Auto Scaling / Docker container :3000
                      └── RDS PostgreSQL :5432
```

### Luồng frontend

1. Browser truy cập hostname mặc định `*.cloudfront.net`.
2. CloudFront lấy file frontend từ S3 private.
3. S3 chỉ cho CloudFront đọc thông qua Origin Access Control (OAC).
4. CloudFront dùng certificate mặc định của AWS; chưa cần custom domain.

### Luồng API

1. Frontend gọi API bằng absolute URL `https://e-commerce-ndt.test/api/...`.
2. Hostname `.test` chỉ được resolve trên máy client test bằng local DNS hoặc `curl --resolve`.
3. ALB lắng nghe HTTPS `443` bằng self-signed certificate đã import vào ACM.
4. Chỉ các CIDR client được khai báo mới được vào ALB HTTPS.
5. ALB forward tới target group HTTP `3000` của EC2.
6. API kết nối RDS qua PostgreSQL `5432`.

## Quyết định và giới hạn

- Đây là hai endpoint người dùng nhìn thấy, không phải một endpoint duy nhất:
  CloudFront phục vụ frontend; ALB phục vụ API.
- Vì hai hostname khác nhau, API phải cấu hình CORS cho origin CloudFront.
- Self-signed certificate chỉ phù hợp cho dev/test. Máy client phải trust certificate,
  nếu không browser sẽ cảnh báo TLS.
- `e-commerce-ndt.test` là domain local, không đăng ký public và không dùng để ACM cấp
  public certificate.
- Không dùng `X-Origin-Verify` làm secret cho browser. Header này chỉ phù hợp với luồng
  CloudFront cũ hoặc kiểm thử thủ công; nếu giữ rule bắt header thì browser gọi API trực
  tiếp sẽ bị `403`.
- Docker là lựa chọn runtime được ghi nhận cho bước triển khai tiếp theo: image được build
  và push ngoài Terraform, sau đó EC2 pull image và publish host port `3000`.

## Trạng thái so với code hiện tại

| Hạng mục | Trạng thái | Ghi chú |
|---|---|---|
| CloudFront → S3 private + OAC | Current | Đã có trong module frontend. |
| CloudFront default domain HTTPS | Current | Không cần custom domain. |
| CloudFront `/api/*` → ALB HTTP | Disabled for dev | Có feature flag để rollback, nhưng `dev` đặt `false`. |
| ALB HTTPS `:443` | Implemented nhưng chưa apply | Dùng imported ACM certificate khi bật biến dev. |
| `e-commerce-ndt.test` local DNS | Planned | Chưa có Terraform resource DNS; cần cấu hình local client. |
| Direct ALB API rule không bắt secret header | Implemented nhưng chưa apply | Rule HTTPS chỉ match `/api` và `/api/*`. |
| Node.js chạy bằng Docker | Implemented nhưng chưa apply | Bootstrap pull image và chạy container; image build/push ngoài Terraform. |

## Thứ tự triển khai sau khi duyệt tài liệu

1. Chốt image runtime: Node.js trực tiếp hoặc Docker image từ Docker Hub.
2. Đặt `enable_cloudfront_api = false` cho environment `dev`.
3. Chỉnh ALB HTTPS rule cho direct API và giữ CIDR allowlist.
4. Nếu chọn Docker, thêm Docker bootstrap, image input và quyền/policy cần thiết.
5. Tạo/trust certificate local và bật imported ACM certificate.
6. Cấu hình CORS và API base URL ở frontend.
7. Chạy `fmt`, `validate`, security checks và `plan -out` để review.
8. Chỉ `apply` sau khi plan artifact được duyệt.

## Tài liệu liên quan

- [Kiến trúc thành phần](../components/README.md)
- [Kế hoạch cấu hình](../configuration/README.md)
- [ALB](../configuration/alb/README.md)
- [Frontend/CloudFront](../configuration/frontend/README.md)
- [Imported ACM certificate](../configuration/certificates/README.md)
- [Compute và Docker](../configuration/compute/README.md)
