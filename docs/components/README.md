# Thành phần hạ tầng

> Đây là sơ đồ kiến trúc theo cấu hình Terraform hiện tại. Sơ đồ mô tả topology và luồng truy cập; không khẳng định tài nguyên đã được `apply` trên AWS.

## Sơ đồ kiến trúc tổng thể

```mermaid
flowchart LR
    user["Người dùng<br/>Browser / Client"]
    cloudfront["Amazon CloudFront<br/>HTTPS viewer<br/>HTTP → HTTPS redirect"]
    frontend["Amazon S3<br/>Private frontend bucket<br/>OAC / SSE-S3"]

    user -->|"HTTPS"| cloudfront
    cloudfront -->|"Default behavior<br/>OAC SigV4"| frontend

    subgraph aws["AWS Region: us-east-1"]
        acm["AWS Certificate Manager<br/>Regional certificate cho ALB<br/>Viewer certificate us-east-1: optional"]
        ssm["AWS Systems Manager<br/>SSM Agent / IAM instance profile"]
        cloudwatch["Amazon CloudWatch<br/>Logs • Metrics • Alarms"]
        artifact["Optional API artifact S3<br/>Bucket/key nằm ngoài module này"]
        secret["Optional database secret<br/>ARN được truyền từ environment"]

        subgraph vpc["VPC 10.0.0.0/16"]
            igw["Internet Gateway"]
            security["Security Groups<br/>CloudFront prefix list → ALB-SG :443<br/>ALB-SG → EC2-SG :3000<br/>EC2-SG → RDS-SG :5432"]

            subgraph public_tier["Public application tier — 2 Availability Zones"]
                subgraph public_az1["Public Subnet 1 — AZ-1"]
                    ec2_1["EC2 API instance 1<br/>NodeJS • public IPv4<br/>IMDSv2 • encrypted gp3"]
                end
                subgraph public_az2["Public Subnet 2 — AZ-2"]
                    ec2_2["EC2 API instance 2<br/>NodeJS • public IPv4<br/>IMDSv2 • encrypted gp3"]
                end
                alb["Internet-facing ALB<br/>spans 2 public subnets<br/>HTTPS :443 • default 403"]
                asg["Auto Scaling Group<br/>min 2 • desired 2 • max 4<br/>CPU target tracking"]
            end

            subgraph database_tier["Private database tier — 2 Database Subnets"]
                subgraph database_az1["Private DB Subnet 1 — AZ-1"]
                    db_subnet_1["DB subnet"]
                end
                subgraph database_az2["Private DB Subnet 2 — AZ-2"]
                    db_subnet_2["DB subnet"]
                end
                rds["Amazon RDS PostgreSQL<br/>1 instance • Single-AZ<br/>private • encrypted"]
            end
        end
    end

    cloudfront -->|"/api/*<br/>HTTPS + X-Origin-Verify"| alb
    alb -->|"HTTP :3000<br/>ALB health check /health"| ec2_1
    alb -->|"HTTP :3000<br/>ALB health check /health"| ec2_2
    ec2_1 -->|"TCP :5432"| rds
    ec2_2 -->|"TCP :5432"| rds

    ec2_1 -->|"Bootstrap / package / artifact"| igw
    ec2_2 -->|"Bootstrap / package / artifact"| igw
    alb -.->|"Internet path"| igw

    acm -.->|"TLS certificate"| cloudfront
    acm -.->|"TLS certificate"| alb
    ssm -.->|"Managed instance access"| ec2_1
    ssm -.->|"Managed instance access"| ec2_2
    artifact -.->|"Optional ZIP download"| ec2_1
    artifact -.->|"Optional ZIP download"| ec2_2
    secret -.->|"Optional runtime reference"| ec2_1
    secret -.->|"Optional runtime reference"| ec2_2

    ec2_1 -->|"Application/system logs<br/>Memory/disk metrics"| cloudwatch
    ec2_2 -->|"Application/system logs<br/>Memory/disk metrics"| cloudwatch
    alb -->|"ALB metrics"| cloudwatch
    asg -->|"ASG metrics"| cloudwatch
    rds -->|"RDS metrics / optional logs"| cloudwatch

    security -.->|"Ingress / egress boundary"| alb
    security -.->|"Ingress / egress boundary"| ec2_1
    security -.->|"Ingress / egress boundary"| ec2_2
    security -.->|"Ingress boundary"| rds

    classDef edge fill:#e0f2fe,stroke:#0284c7,color:#0c4a6e
    classDef public fill:#fef3c7,stroke:#d97706,color:#78350f
    classDef private fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef ops fill:#f3e8ff,stroke:#9333ea,color:#581c87
    classDef security fill:#fee2e2,stroke:#dc2626,color:#7f1d1d

    class user,cloudfront,frontend edge
    class alb,ec2_1,ec2_2,asg,igw public
    class db_subnet_1,db_subnet_2,rds private
    class acm,ssm,cloudwatch,artifact,secret ops
    class security security
```

Ghi chú: kiến trúc hiện tại không dùng NAT Gateway. EC2 API chạy trong public subnet và có public IPv4 để bootstrap/outbound qua Internet Gateway, nhưng application port `3000` không mở trực tiếp ra Internet. RDS có DB subnet group trải trên hai AZ nhưng chỉ chạy một instance Single-AZ. Viewer hiện tại dùng hostname mặc định `*.cloudfront.net`; custom viewer domain và certificate `us-east-1` là cải tiến tương lai.

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
