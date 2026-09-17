# Kiến trúc hiện tại

## Sơ đồ tổng thể

```mermaid
flowchart LR
    user["Người dùng"]
    cloudfront["CloudFront<br/>HTTPS"]

    subgraph aws["AWS — environment dev"]
        s3["S3 private<br/>Frontend"]

        subgraph vpc["VPC"]
            subgraph public["Public subnets — 2 AZ"]
                alb["Application Load Balancer<br/>HTTP :80"]
                asg["EC2 Auto Scaling Group<br/>Node.js API<br/>2 instances trở lên"]
            end

            subgraph private["Private database subnets"]
                rds["RDS PostgreSQL<br/>Single-AZ"]
            end
        end

        cloudwatch["CloudWatch<br/>Logs và Alarms"]
    end

    user -->|"HTTPS"| cloudfront
    cloudfront -->|"Website tĩnh"| s3
    cloudfront -->|"/api/* — HTTP"| alb
    alb -->|"HTTP :3000"| asg
    asg -->|"PostgreSQL :5432"| rds

    alb -.->|"Metrics"| cloudwatch
    asg -.->|"Logs / Metrics"| cloudwatch
    rds -.->|"Logs / Metrics"| cloudwatch

    classDef entry fill:#dbeafe,stroke:#2563eb,color:#1e3a8a
    classDef publicTier fill:#fef3c7,stroke:#d97706,color:#78350f
    classDef privateTier fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef ops fill:#f3e8ff,stroke:#9333ea,color:#581c87

    class user,cloudfront entry
    class s3,alb,asg publicTier
    class rds privateTier
    class cloudwatch ops
```



## Lưu ý đúng với cấu hình hiện tại

- CloudFront đang dùng hostname mặc định `*.cloudfront.net` và certificate mặc định của CloudFront.
- CloudFront → ALB đang dùng HTTP; ALB lắng nghe port `80`.
- ALB → EC2 dùng HTTP port `3000`; EC2 → RDS dùng PostgreSQL port `5432`.
- EC2 nằm trong public subnets; RDS nằm trong private database subnets và hiện là Single-AZ.
- Đây là sơ đồ khái niệm phục vụ thuyết trình; xem [sơ đồ chi tiết](../components/README.md) khi cần security groups, Internet Gateway và module wiring.

## Mapping với Terraform modules

| Thành phần | Module |
|---|---|
| VPC và subnets | [`network`](../../modules/network) |
| Frontend và CloudFront | [`frontend`](../../modules/frontend) |
| ALB | [`alb`](../../modules/alb) |
| EC2 Auto Scaling Group | [`compute`](../../modules/compute) |
| RDS PostgreSQL | [`database`](../../modules/database) |
| Logs và alarms | [`monitoring`](../../modules/monitoring) |
