# Kế hoạch cấu hình: network

## Mục tiêu

Tạo ranh giới mạng cho toàn bộ hệ thống: một VPC, hai public subnets cho ALB và EC2, hai database subnets cho RDS, cùng định tuyến tách biệt.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| Amazon VPC | Một VPC, CIDR được truyền từ environment. |
| Availability Zones | Chính xác hai AZ để phân bố public/database subnets. |
| Public subnets | Mỗi AZ một subnet; route mặc định đi Internet Gateway. Dùng cho ALB và EC2 ASG. |
| Database subnets | Mỗi AZ một subnet; không có route Internet trực tiếp. Dùng cho DB subnet group của RDS. |
| Internet Gateway | Gắn với VPC, phục vụ outbound/inbound của public subnets. |
| Route tables | Một nhóm route table public và một nhóm database, gắn đúng từng subnet. |

## Input cần quyết định

| Nhóm | Giá trị cần cung cấp |
|---|---|
| Định danh | `project_name`, `environment`, common tags. |
| Không gian địa chỉ | VPC CIDR; hai CIDR public; hai CIDR database, không chồng lấn. |
| Tính sẵn sàng | Danh sách đúng hai AZ trong cùng region. |

## Output contract

- VPC ID và VPC CIDR cho security groups, ALB và các service phụ thuộc.
- Danh sách public subnet IDs cho ALB và compute.
- Danh sách database subnet IDs cho database module.
- Danh sách AZ đã chọn để kiểm tra phân bố tài nguyên.

## Điều kiện chấp nhận

- Mỗi loại subnet có một subnet ở mỗi AZ.
- Chỉ public subnets có default route qua Internet Gateway.
- Database subnets không được dùng để đặt EC2 public-facing hoặc ALB.
