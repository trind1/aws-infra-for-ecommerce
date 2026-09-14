# Thành phần hạ tầng

> Đây là kiến trúc mục tiêu. Các tài liệu trong [`docs/configuration/`](../configuration/README.md) là kế hoạch cấu hình theo từng module; chúng không khẳng định trạng thái HCL hiện tại.

## Kiến trúc dự kiến

```text
Người dùng
  │ HTTPS tới https://<distribution>.cloudfront.net
  │ CloudFront mặc định dùng certificate do CloudFront cung cấp
  ▼
CloudFront ──OAC──► S3 private bucket (frontend tĩnh)
  │ /api/* + custom origin header
  │ HTTPS tới ALB origin domain
  ▼
ALB (public subnets) ──HTTP──► EC2 Auto Scaling Group (public subnets)
                                      │ DB port
                                      ▼
                              RDS Single-AZ (private DB subnets)

CloudWatch nhận log/metric/alarm từ ALB, EC2/ASG, RDS và application.
```

Kiến trúc không dùng NAT Gateway. EC2 API chạy trong public subnet để bootstrap và đi Internet qua Internet Gateway, nhưng application port chỉ được security group cho phép từ ALB. Viewer hiện tại dùng hostname mặc định `*.cloudfront.net`; custom viewer domain là cải tiến tương lai.

## Cây tài liệu

```text
docs/
├── components/
│   └── README.md                 # Kiến trúc và các luồng tổng thể
└── configuration/
    ├── README.md                 # Thứ tự cấu hình và quan hệ module
    ├── network/README.md
    ├── security-groups/README.md
    ├── certificates/README.md
    ├── alb/README.md
    ├── frontend/README.md
    ├── database/README.md
    ├── monitoring/README.md
    └── compute/README.md
```

## Danh mục module

| Module | Mục tiêu |
|---|---|
| [`network`](../configuration/network/README.md) | VPC, hai public subnets, hai database subnets, Internet Gateway và định tuyến. |
| [`security-groups`](../configuration/security-groups/README.md) | Chuỗi truy cập CloudFront → ALB → application → database. |
| [`certificates`](../configuration/certificates/README.md) | Certificate regional cho ALB origin HTTPS; certificate `us-east-1` cho custom viewer domain là optional/future. |
| [`alb`](../configuration/alb/README.md) | Public ALB, API target group, listener và kiểm tra custom origin header. |
| [`frontend`](../configuration/frontend/README.md) | S3 private, OAC, CloudFront distribution và API behavior `/api/*`. |
| [`database`](../configuration/database/README.md) | DB subnet group, một RDS Single-AZ và RDS engine logs. |
| [`monitoring`](../configuration/monitoring/README.md) | CloudWatch log groups, metric filters, alarms cho ALB/ASG/RDS/API. |
| [`compute`](../configuration/compute/README.md) | IAM, launch template, EC2 Auto Scaling Group và CPU target tracking. |

## Luồng mạng và kiểm soát truy cập

| Luồng | Nguồn → đích | Cấu hình mục tiêu |
|---|---|---|
| Frontend tĩnh | Viewer → CloudFront → S3 | OAC và bucket policy; S3 không public. |
| API công khai | Viewer `*.cloudfront.net` → CloudFront → ALB | Behavior `/api/*`; CloudFront gửi custom origin header và mục tiêu kết nối tới ALB bằng HTTPS. |
| Vào ALB | CloudFront prefix list → ALB SG | Chỉ managed prefix list origin-facing của CloudFront được vào listener. |
| Tới application | ALB SG → application SG | Chỉ application port được phép. |
| Tới database | Application SG → database SG | Chỉ DB port được phép. |
| Outbound application | EC2 public subnet → IGW | Bootstrap, tải package/artifact; không có NAT Gateway. |

## Domain và certificate độc lập

- **Viewer domain:** giai đoạn hiện tại là `https://<distribution>.cloudfront.net`, dùng certificate mặc định của CloudFront. Không cần mua domain riêng, Route 53 hosted zone, CloudFront alias hoặc ACM certificate `us-east-1` cho luồng này.
- **ALB origin domain:** là hostname CloudFront dùng để kết nối tới ALB. Luồng CloudFront → ALB có mục tiêu HTTPS và cần certificate regional của ALB khớp hostname này; nó độc lập với viewer domain.
- **Custom viewer domain:** `Optional / Future improvement`. Khi bật mới cần domain riêng, DNS, CloudFront alias và certificate phù hợp tại `us-east-1`; không thay thế certificate regional của ALB.

## Quyết định cần chốt trước khi triển khai

- CIDR VPC, hai Availability Zones và dải CIDR của từng loại subnet.
- ALB origin domain, DNS provider/zone và phương án cấp/validate certificate regional khớp domain đó. Đây là quyết định đang mở và chặn việc khẳng định HTTPS CloudFront → ALB đã sẵn sàng.
- AMI, instance type, dung lượng ASG, artifact khởi chạy API và nơi lưu secret database.
- Engine/version/class/storage, backup, maintenance và deletion protection của RDS.
- Ngưỡng alarm, kênh nhận cảnh báo và retention của log.
- Custom viewer domain, CloudFront alias và certificate `us-east-1` chỉ là quyết định tương lai, không phải điều kiện của URL mặc định.

Xem thứ tự wiring và các contract input/output tại [kế hoạch cấu hình](../configuration/README.md).
