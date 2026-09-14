# Module: Network

Tạo network infrastructure cho kiến trúc three-tier trên AWS, gồm VPC, public subnets cho ALB và EC2, private database subnets cho RDS, Internet Gateway và các Route Tables tương ứng.

Module này cố ý không tạo NAT Gateway. Theo kiến trúc mục tiêu, application instances chạy trong public subnets và database tier được cô lập trong private subnets không có default route ra Internet.

---

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_vpc` | 1 | VPC chính, bật DNS support và DNS hostnames. |
| `aws_internet_gateway` | 1 | Internet Gateway gắn với VPC. |
| `aws_subnet` (public) | 2 | Public subnets, mỗi subnet nằm trong một Availability Zone; dùng cho ALB và EC2/ASG. |
| `aws_subnet` (database) | 2 | Private database subnets, mỗi subnet nằm trong một Availability Zone; dùng cho RDS. |
| `aws_route_table` (public) | 1 | Route `0.0.0.0/0` tới Internet Gateway. |
| `aws_route_table_association` (public) | 2 | Gắn public route table vào hai public subnets. |
| `aws_route_table` (database) | 1 | Route table không có default route ra Internet. |
| `aws_route_table_association` (database) | 2 | Gắn database route table vào hai database subnets. |

---

## Network Design

Với giá trị dev mặc định ở `environments/dev/variables.tf`, topology có dạng:

```text
VPC (10.0.0.0/16)
│
├── Public Subnets
│   ├── 10.0.1.0/24 · us-east-1a
│   └── 10.0.2.0/24 · us-east-1b
│       ALB · EC2/ASG
│
└── Private Database Subnets
    ├── 10.0.21.0/24 · us-east-1a
    └── 10.0.22.0/24 · us-east-1b
        RDS Single-AZ
```

### Traffic separation

- **Public subnets:** `map_public_ip_on_launch = true`; route outbound `0.0.0.0/0` qua Internet Gateway. Dùng cho ALB và EC2/ASG theo thiết kế mục tiêu.
- **Database subnets:** không bật public IP; route table không có default route nên RDS không có đường Internet trực tiếp.
- **Internet Gateway:** là next hop của public route table; module không tạo NAT Gateway.
- **Security groups:** không thuộc module này. Các rule CloudFront → ALB → application → database được quản lý bởi module `security-groups`.

### Route flow

```text
Public subnet
  └── public route table
        └── 0.0.0.0/0 → Internet Gateway

Database subnet
  └── database route table
        └── no default route
```

---

## Variables

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `project_name` | `string` | Yes | Tên project, dùng làm prefix khi đặt tên tài nguyên. |
| `environment` | `string` | Yes | Môi trường triển khai, ví dụ `dev` hoặc `prod`. |
| `vpc_cidr` | `string` | Yes | CIDR block của VPC, ví dụ `10.0.0.0/16`. |
| `availability_zones` | `list(string)` | Yes | Chính xác hai AZ; thứ tự phải khớp với các danh sách subnet CIDR. |
| `public_subnet_cidrs` | `list(string)` | Yes | Chính xác hai CIDR cho public subnets. |
| `database_subnet_cidrs` | `list(string)` | Yes | Chính xác hai CIDR cho private database subnets. |

### Input validation

- `vpc_cidr` phải là CIDR hợp lệ.
- `availability_zones` phải có đúng hai AZ khác nhau.
- `public_subnet_cidrs` phải có đúng hai CIDR hợp lệ.
- `database_subnet_cidrs` phải có đúng hai CIDR hợp lệ.
- Thứ tự phần tử trong `availability_zones`, `public_subnet_cidrs` và `database_subnet_cidrs` phải tương ứng theo index.
- Các CIDR subnet phải nằm trong VPC và không được overlap; đây là điều kiện cần kiểm tra ở composition/plan khi thay đổi giá trị environment.

---

## Outputs

| Name | Description | Used by |
|------|-------------|---------|
| `vpc_id` | ID của VPC. | `security-groups`, `alb` và các module cần VPC. |
| `vpc_cidr_block` | CIDR block của VPC. | Composition layer và network policy. |
| `public_subnet_ids` | Danh sách public subnet IDs theo thứ tự subnet. | `alb`, `compute`. |
| `database_subnet_ids` | Danh sách private database subnet IDs theo thứ tự subnet. | `database`. |
| `availability_zones` | Hai AZ được sử dụng bởi các subnet pairs. | Composition và các module phụ thuộc. |

---

## Resource naming

Tên tài nguyên dùng prefix:

```text
<project_name>-<environment>
```

Ví dụ:

```text
aws-infra-for-ecommerce-dev
aws-infra-for-ecommerce-dev-igw
aws-infra-for-ecommerce-dev-public-1
aws-infra-for-ecommerce-dev-db-1
```

Các resource được tạo bằng `for_each` với key ổn định (`1`, `2`) để tránh thay đổi địa chỉ Terraform khi chỉ cập nhật giá trị không liên quan.

---

## Notes

- Module chỉ tạo network foundation; không tạo ALB, EC2, RDS hoặc security groups.
- Tags `Name`, `Component` và `Tier` do module gán trực tiếp; tags chung (`Project`, `Environment`, `ManagedBy`) do provider `default_tags` áp dụng.
- Public route table có route Internet Gateway; database route table để trống default route là chủ ý bảo mật.
- Không có NAT Gateway nên EC2 trong public subnet dùng public IPv4 và Internet Gateway cho bootstrap/outbound.
- Database subnet không có đường Internet trực tiếp; traffic tới RDS phải được giới hạn bởi security group ở module database/security-groups.
- Với production, cần cân nhắc VPC Flow Logs, endpoint services hoặc mô hình private application subnet riêng nếu yêu cầu bảo mật thay đổi.
- Trước khi apply, cần kiểm tra CIDR không overlap và xác nhận hai AZ cùng region với `aws_region`.
