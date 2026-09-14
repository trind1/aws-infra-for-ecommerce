# Module: Security Groups

Tạo các security groups và rule kiểm soát traffic cho kiến trúc three-tier:

```text
CloudFront origin-facing prefix list
              │ listener port
              ▼
           ALB-SG
              │ application port
              ▼
          Application-SG
              │ database port
              ▼
          Database-SG
```

Module này chỉ quản lý network security layer. ALB, EC2, RDS và việc kiểm tra custom origin header được quản lý bởi các module riêng.

---

## Resources Created

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_security_group.alb` | 1 | Security group cho internet-facing ALB. |
| `aws_security_group.app` | 1 | Security group cho API EC2/Auto Scaling Group. |
| `aws_security_group.database` | 1 | Security group cho RDS. |
| `aws_vpc_security_group_ingress_rule` | 3 | Rule vào ALB từ CloudFront và vào application/database từ security group nội bộ. |
| `aws_vpc_security_group_egress_rule` | 3 | Rule từ ALB tới application, application tới database và outbound phục vụ bootstrap/AWS services. |

Các rule được quản lý bằng resource riêng thay vì block `ingress`/`egress` inline trong `aws_security_group`.

---

## Traffic Rules

| Security group | Direction | Source/Destination | Port | Protocol | Mục đích |
|---|---|---|---:|---|---|
| ALB-SG | Ingress | CloudFront origin-facing managed prefix list | `alb_listener_port` | TCP | Chỉ CloudFront được vào listener của ALB. |
| ALB-SG | Egress | Application-SG | `application_port` | TCP | ALB forward request tới API. |
| Application-SG | Ingress | ALB-SG | `application_port` | TCP | EC2 chỉ nhận traffic application từ ALB. |
| Application-SG | Egress | Database-SG | `database_port` | TCP | API kết nối tới database. |
| Application-SG | Egress | `0.0.0.0/0` | All | All | Bootstrap, tải package/artifact, SSM và CloudWatch qua public subnet/IGW. |
| Database-SG | Ingress | Application-SG | `database_port` | TCP | RDS chỉ nhận kết nối từ API. |

### Security behavior

- Không có ingress `0.0.0.0/0` vào application hoặc database.
- Không mở SSH hoặc application port trực tiếp từ Internet.
- Traffic giữa các tier dùng `referenced_security_group_id`, không hard-code IP instance.
- Database security group không có egress rule mới. Security group của AWS là stateful nên response traffic của kết nối hợp lệ vẫn được trả về.
- Application outbound tới `0.0.0.0/0` là trade-off của kiến trúc hiện tại: EC2 nằm trong public subnet và cần Internet Gateway cho bootstrap/AWS service access. Có thể thu hẹp sau khi bổ sung VPC endpoints và danh sách destination cụ thể.
- Custom origin header không thể được kiểm tra bởi security group; rule HTTP header thuộc module `alb`.

---

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `project_name` | `string` | Yes | Tên project, dùng làm prefix cho tên security group. |
| `environment` | `string` | Yes | Tên môi trường, ví dụ `dev` hoặc `prod`. |
| `vpc_id` | `string` | Yes | VPC ID nhận từ module `network`. |
| `cloudfront_origin_prefix_list_id` | `string` | Yes | ID managed prefix list origin-facing của CloudFront trong AWS region đang triển khai. |
| `alb_listener_port` | `number` | Yes | Port ALB nhận traffic từ CloudFront. |
| `application_port` | `number` | Yes | Port API application nhận traffic từ ALB. |
| `database_port` | `number` | Yes | Port database nhận traffic từ application. |

Tags chung (`Project`, `Environment`, `ManagedBy`) không phải input của module; chúng được provider `default_tags` áp dụng. Module chỉ thêm tags riêng `Name`, `Component` và `Tier`.

---

## Outputs

| Name | Description | Used by |
|------|-------------|---------|
| `alb_security_group_id` | ID security group của ALB. | Module `alb`. |
| `application_security_group_id` | ID security group của API EC2/ASG. | Module `compute`. |
| `database_security_group_id` | ID security group của RDS. | Module `database`. |

---

## Naming and dependencies

Tên security group dùng prefix:

```text
<project_name>-<environment>-<tier>-sg
```

Ví dụ:

```text
aws-infra-for-ecommerce-dev-alb-sg
aws-infra-for-ecommerce-dev-app-sg
aws-infra-for-ecommerce-dev-db-sg
```

Module nhận `vpc_id` từ `module.network`. Environment truyền ba output security group tới các module downstream bằng reference trực tiếp, không truyền resource object nội bộ.

---

## Notes

- Managed prefix list ID là input bắt buộc vì ID có thể thay đổi theo AWS region; environment phải cung cấp đúng ID của region đang dùng.
- Security group chỉ là một lớp kiểm soát. ALB vẫn cần rule kiểm tra custom origin header để hạn chế request bypass CloudFront.
- Nếu thay đổi tên hoặc địa chỉ resource sau khi đã apply, cần kiểm tra plan và dùng `moved` block khi phù hợp để tránh recreate security group đang được resource khác tham chiếu.
- Module không tạo NACL, WAF, ALB listener, IAM policy, VPC endpoint hoặc NAT Gateway.
