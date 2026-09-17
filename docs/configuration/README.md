# Kế hoạch cấu hình

Các tài liệu này chuyển kiến trúc trong [`docs/components/`](../components/README.md) thành contract cấu hình cho từng module. Chúng là mục tiêu triển khai, độc lập với các file Terraform đang có.

## Phạm vi và nguyên tắc

- Mỗi module chỉ sở hữu một nhóm tài nguyên có trách nhiệm rõ ràng.
- Environment composition truyền giá trị cụ thể và nối các output vào input; module không tự suy đoán hạ tầng bên ngoài.
- Secret database, giá trị custom header và địa chỉ nhận cảnh báo không ghi trực tiếp trong mã hoặc tài liệu ví dụ. Database module nhận master password qua secret injection nhưng không tự tạo/đọc Secrets Manager secret.
- Mọi output được tiêu thụ bởi module khác phải là contract ổn định, có mô tả rõ mục đích.

## Thứ tự cấu hình

```text
network
  ├── security-groups
  └── monitoring (log foundation)
                         ├── alb ──► frontend
                         ├── compute ──► monitoring (alarms/metrics)
                         └── database ─► monitoring (alarms/metrics)
```

`monitoring` được chia theo hai pha logic: tạo log groups trước để `compute` có thể ghi log, sau đó tạo alarms khi đã có ALB, ASG và RDS. Cách này tránh vòng phụ thuộc giữa compute và monitoring.

## Danh sách module

| Module | Tài liệu | Phụ thuộc đầu vào | Cung cấp cho |
|---|---|---|---|
| Network | [README](network/README.md) | CIDR, AZs | Security groups, ALB, compute, database |
| Security groups | [README](security-groups/README.md) | VPC, ports, CloudFront prefix list | ALB, compute, database |
| Certificates | [README](certificates/README.md) | Reusable cho HTTPS environment; không dùng trong dev hiện tại | Environment HTTPS |
| ALB | [README](alb/README.md) | VPC, public subnets, ALB SG, HTTP listener, origin header | Frontend, compute, monitoring |
| Frontend | [README](frontend/README.md) | ALB DNS name, HTTP origin/header, default viewer certificate | Người dùng cuối |
| Database | [README](database/README.md) | DB subnets, DB SG, out-of-band credentials | Compute, monitoring |
| Monitoring | [README](monitoring/README.md) | Tên/tài nguyên ALB, ASG, RDS | Compute và vận hành |
| Compute | [README](compute/README.md) | Public subnets, app SG, target group, DB, log groups | ALB, monitoring |

## Contract tối thiểu ở composition layer

1. `network` xuất VPC ID, public subnet IDs và database subnet IDs.
2. `security-groups` nhận VPC ID, xuất ba security group IDs.
3. `alb` nhận public subnets, ALB SG, HTTP listener và origin header; xuất target group, listener, DNS/ARN và metric suffixes.
4. Composition layer định nghĩa ASG naming contract ổn định cho monitoring alarms; `monitoring` sở hữu log foundation và xuất tên log groups cho `compute`.
5. `compute` nhận target group, app SG, database connection metadata và monitoring log outputs; xuất ASG name.
6. `database` xuất endpoint, port, identifier và log group metadata; không xuất credential value. Master password phải được inject ngoài mã nguồn và bảo vệ trong backend state.
7. `monitoring` pha alarms nhận identity của ALB, ASG và RDS; không yêu cầu compute phụ thuộc ngược vào alarms.
8. `frontend` dùng URL mặc định `*.cloudfront.net` và certificate mặc định của CloudFront; nhận ALB DNS name/protocol HTTP và header bí mật. HTTPS origin là phương án riêng cho production.

## Kiểm tra thiết kế trước khi áp dụng

- Không có đường Internet trực tiếp vào S3, application port hay database port.
- ALB chỉ nhận traffic origin-facing từ CloudFront; API header là lớp kiểm tra bổ sung, không thay thế security group.
- RDS ở database subnet, không gán public IP, chỉ có một instance Single-AZ theo phạm vi hiện tại.
- Client → CloudFront dùng certificate mặc định của CloudFront với URL `*.cloudfront.net`; không cần custom viewer domain, Route 53 hosted zone hoặc certificate `us-east-1` ở giai đoạn hiện tại.
- CloudFront → ALB dùng HTTP trong dev/test; không có certificate hoặc origin domain riêng.
- Production HTTPS origin cần certificate regional và hostname phù hợp; không dùng HTTP config này cho production.
- Không hình thành dependency cycle qua output log groups và alarm resources.
