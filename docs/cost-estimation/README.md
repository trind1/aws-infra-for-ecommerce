# AWS Pricing Calculator: cấu hình nhập và ước tính chi phí

> Tài liệu này mô tả cách nhập kiến trúc hiện tại vào [AWS Pricing Calculator](https://calculator.aws/#/addService). Đây là **ước tính chi phí**, không phải hóa đơn và không xác nhận hạ tầng đã được `apply`.

## Mục tiêu và nguyên tắc đọc

Không thể chứng minh một tổng chi phí “chính xác tuyệt đối” chỉ từ HCL. AWS còn tính theo traffic, số request, GB log, dữ liệu backup, LCU và vùng người dùng. Tài liệu này cung cấp:

- danh sách đầy đủ các service/resource cần nhập;
- giá trị lấy từ cấu hình hiện tại;
- các usage assumption cần chốt;
- công thức kiểm tra chéo với Calculator;
- evidence code và nguồn giá chính thức.

Muốn có con số cuối cùng, cần lưu lại URL/PDF của estimate sau khi nhập các usage assumption. Không đưa URL estimate chưa tồn tại vào tài liệu này.

AWS Pricing Calculator chỉ tính trên các thông tin đã nhập; AWS cho biết giá trong estimate lấy từ AWS Price List API và cho phép xem calculation, lưu share URL hoặc export CSV/PDF. Vì vậy, evidence của tài liệu gồm hai phần: **cấu hình Terraform cho các giá trị cố định** và **estimate artifact của Calculator cho giá/usage đã nhập**. Xem [tài liệu AWS Pricing Calculator](https://docs.aws.amazon.com/pricing-calculator/latest/userguide/what-is-pricing-calculator.html).

## 1. Bản đồ nhận diện service trên AWS Pricing Calculator

Mở [AWS Pricing Calculator - Estimate](https://calculator.aws/#/estimate), chọn **Add service** và tìm theo cột **Tên cần tìm**. Đây là mapping giữa tên hiển thị cần nhận diện trong Calculator và cấu hình Terraform của repository:

| # | Tên cần tìm trong Calculator | Chọn cấu hình nào | Mapping Terraform | Có nhập riêng không? |
|---:|---|---|---|---|
| 1 | **Amazon EC2** | Linux, Shared tenancy, On-Demand, `t3.micro`, 2 instance chạy thường xuyên, 730 giờ/tháng | ASG API dùng `t3.micro`; desired/min = 2 | Có |
| 2 | **Amazon Elastic Block Store (EBS) - optional** trong form EC2 | Storage for each EC2 instance = `20 GB`; 2 instance months tạo ra tổng 40 GB-month provisioned | Root EBS `20 GiB/instance` | Khuyến nghị nhập trong EC2; chỉ dùng service riêng nếu UI không có component này |
| 3 | **Elastic Load Balancing** | **Application Load Balancer**, 1 ALB, 730 giờ, giả định khoảng 0.1 LCU trung bình | 1 `aws_lb` internet-facing trên 2 public subnets | Có |
| 4 | **Amazon RDS for PostgreSQL** | PostgreSQL, `db.t3.micro`, Single-AZ, gp3, 20 GiB, 730 giờ | 1 `aws_db_instance`, private, `multi_az = false` | Có |
| 5 | **Amazon S3** | S3 Standard, 5 GB baseline cho frontend, 1,000 PUT/LIST và 1,000,000 GET/month; thêm artifact bucket nếu được cấu hình | 1 private frontend bucket; API artifact bucket là input tùy chọn | Có |
| 6 | **Amazon CloudFront** | Pay-as-you-go, `PriceClass_100`, data out và HTTPS requests theo usage | 1 distribution, S3 origin + ALB origin | Có |
| 7 | **Amazon CloudWatch** | 7 standard alarms, 2 log groups, log ingestion và custom metrics theo usage | 7 alarms, 2 log groups, 1 metric filter | Có |
| 8 | **Amazon Virtual Private Cloud (VPC)** | Chỉ chọn **Public IPv4 Address**; In-use `4`, Idle `0`. VPN, NAT Gateway, Transit Gateway, PrivateLink và các feature khác không chọn | 1 VPC; 2 public subnets; 2 database subnets; không có NAT Gateway | Có; nhập đúng component có usage |

### 1.1. Những resource không tạo line item riêng

Các resource dưới đây đã được tính bên trong service cha hoặc không có line item trực tiếp. Không tạo thêm một service estimate cho chúng:

| Resource Terraform | Đã nằm trong | Cách xử lý |
|---|---|---|
| VPC, subnet, route table, route association, Internet Gateway | Amazon VPC | Không cộng thêm phí; chỉ nhập Public IPv4 nếu Calculator yêu cầu |
| Security groups và security-group rules | Không có service charge riêng | Không nhập |
| Auto Scaling Group | Amazon EC2 | Chỉ tính số EC2 instance thực tế và các metric liên quan |
| Target group, listener, listener rule | Elastic Load Balancing | Không tính thành ALB thứ hai |
| CloudFront OAC, behavior `/api/*`, custom origin header | Amazon CloudFront | Không nhập thành service riêng |
| S3 public-access block, ownership, versioning, encryption | Amazon S3 | Không tạo bucket thứ hai; versioning có thể làm tăng storage thực tế nếu giữ nhiều phiên bản |
| API artifact bucket | Amazon S3 | Không do repository tạo. Nếu `application_artifact_bucket` là bucket của account này, phải cộng storage, request và data transfer của bucket đó |
| IAM role, policy, instance profile | Không có service charge trực tiếp | Không nhập |
| ACM ALB certificate và DNS validation record | Không có monthly charge riêng cho public ACM certificate tích hợp | Không nhập ACM như một dịch vụ tính phí |
| NAT Gateway | Không có trong kiến trúc hiện tại | Không nhập |
| SNS topic | Không được module này tạo | Chỉ nhập nếu có resource bên ngoài repository |

### 1.2. Trình tự nhập để dễ đối chiếu

Nhập theo thứ tự **EC2 (bao gồm EBS optional) → ELB → RDS PostgreSQL → S3 → CloudFront → CloudWatch → VPC (Public IPv4)**. Sau mỗi service, đặt tên line item có prefix giống cấu hình, ví dụ `dev-api-ec2`, `dev-alb`, `dev-rds-postgres`, để tổng Calculator có thể đối chiếu ngược với inventory Terraform. Không gộp RDS vào EC2 hoặc gộp CloudFront vào S3.

## 2. Phạm vi và giả định baseline

| Thuộc tính | Giá trị dùng cho baseline |
|---|---|
| Ngày tham chiếu | `2026-09-15` |
| Region | `us-east-1` |
| Environment | `dev` |
| Thời gian | 730 giờ/tháng, chạy 24x7 |
| Pricing model | On-Demand, Linux, không Reserved/Savings Plan |
| Thuế, credits, discount | Chưa tính trong baseline |
| ASG steady state | 2 instance; `max_size = 4` chỉ là giới hạn scale-out |
| EC2 | `t3.micro`, detailed monitoring tắt, root volume gp3 20 GiB/instance |
| RDS | PostgreSQL `db.t3.micro`, Single-AZ, gp3 20 GiB |
| ALB | 1 internet-facing ALB trên 2 AZ, giả định tải nhỏ khoảng 0.1 LCU trung bình |
| CloudFront | Pay-as-you-go, `PriceClass_100`, giả định 100 GB data out và 10M HTTPS requests/tháng |
| S3 | Frontend bucket S3 Standard, 5 GB storage, 1,000 PUT/LIST và 1,000,000 GET mỗi tháng trong baseline; API artifact bucket là tùy chọn |
| CloudWatch Logs | Standard Logs ingestion `2 GB/tháng` trong baseline; Infrequent Access và vended logs = `0` |
| Route 53 | Không tính hosted zone trong baseline; custom viewer domain đang tắt |

Các giá trị usage như 100 GB, 10M CloudFront requests, 5 GB S3, 1,000 PUT/LIST, 1,000,000 GET, 2 GB CloudWatch Standard Logs và 87,600 API requests là **baseline assumption để nhập Calculator**, không phải số liệu runtime đã đo của repository.

## 3. Phiếu nhập nhanh theo thứ tự Calculator

Bảng này là bộ giá trị baseline để nhập lần đầu. Nhập theo thứ tự từ trên xuống dưới. Cột **Nguồn** cho biết giá trị là cấu hình đọc được từ repository hay giả định cần thay bằng usage thực tế.

| Thứ tự | Service trong Calculator | Các giá trị nhập chính | Nguồn |
|---:|---|---|---|
| 1 | **Amazon EC2** | Region `US East (N. Virginia)`; Shared Instances; Linux; Constant usage; `2` instances; chọn `t3.micro`; On-Demand; utilization `100%` | Terraform: loại máy và số instance |
| 2 | **EBS - optional** trong form EC2 | Per instance `20 GB`; `General Purpose SSD (gp3)`; IOPS `3,000`; Throughput `125 MBps`; Snapshot Frequency `No snapshot storage` | Terraform: root volume; gp3 baseline |
| 3 | **Elastic Load Balancing** | Application Load Balancer; `1` ALB; `730` giờ; Lambda bytes `0 GB/hour`; EC2/IP bytes `0.1 GB/hour`; new connections `1/second`; duration `1 second`; requests `2/connection`; rule evaluations `1/request` | Terraform: 1 ALB; phần LCU là giả định |
| 4 | **Amazon RDS for PostgreSQL** | Region `US East (N. Virginia)`; Nodes `1`; `db.t3.micro`; utilization `100%`; Single-AZ; OnDemand; RDS Proxy `No`; gp3 `20 GB`; Database Insights `No`; Extended Support `No`; additional backup `0 GB`; snapshot export `0 GB/month`; read replicas `0` | Terraform: engine, instance, storage, Single-AZ |
| 5 | **Amazon Simple Storage Service (S3)** | Chỉ chọn S3 Standard; storage `5 GB/month`; data already in S3 Standard; PUT/COPY/POST/LIST `1,000 requests/month`; GET/SELECT/other `1,000,000 requests/month`; S3 Select returned/scanned `0 GB/month` | Bucket là Terraform; dung lượng/request là giả định |
| 6 | **Amazon CloudFront** | Region `US East (N. Virginia)`; chọn Pay as you go; Edge Locations chỉ `United States`; data out `100 GB/month`; data out to origin `0 GB/month`; HTTPS requests `10,000,000/month`; distributions `1`; Price Class `PriceClass_100`; invalidations `0`; Functions/Lambda@Edge `0` | Terraform: distribution/price class; traffic là giả định |
| 7 | **Amazon CloudWatch** | Region `US East (N. Virginia)`; Metrics `7`; GetMetricData `0`; GetMetricWidgetImage `0`; other API requests `87,600/month`; RDS/Aurora Database Insights `0`; Standard Logs ingestion `2 GB`; Infrequent Access/vended logs `0`; log storage `Yes`, `1 month`; Logs Insights `0`; standard alarms `7`; dashboards `0`; Canaries/Contributor Insights/other Insights `Not configured`; RUM mobile events/visit `70`, sampling `100%` nhưng mobile visits `0` | Terraform: alarms/log groups; metric/API/log volume và RUM fields có phần giả định |
| 8 | **Amazon VPC → Public IPv4 Address** | In-use `4`; Idle `0` | Baseline: 2 EC2 + 2 địa chỉ cho ALB trên 2 AZ |

Không nhập `max_size = 4` thành bốn EC2 chạy liên tục; không nhập EBS hai lần; không thêm Route 53 hoặc ACM viewer certificate trong baseline; không thêm NAT Gateway. Các giá trị `0.1 LCU`, `5 GB S3`, `100 GB CloudFront`, `10M CloudFront requests`, `2 GB CloudWatch Standard Logs` và `87,600 API requests` là **số để nhập**, không phải evidence usage đã đo.

## 4. Inventory Terraform và evidence

| Nhóm | Resource/service | Số lượng hoặc cấu hình suy ra | Evidence code |
|---|---|---|---|
| Network | VPC, subnets, route tables, IGW | 1 VPC; 2 public subnets; 2 database subnets; không có NAT Gateway | [`../../modules/network/main.tf`](../../modules/network/main.tf#L22) |
| Security | Security groups và SG rules | 3 security groups, rule standalone | [`../../modules/security-groups/main.tf`](../../modules/security-groups/main.tf#L6) |
| Load balancing | Application Load Balancer | 1 ALB, 2 public AZs, 1 target group | [`../../modules/alb/main.tf`](../../modules/alb/main.tf#L3) |
| Compute | EC2 Auto Scaling Group | desired/min 2, max 4, `t3.micro` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L410), [`../../modules/compute/main.tf`](../../modules/compute/main.tf#L249) |
| Block storage | EC2 root EBS | gp3 20 GiB × 2 steady-state instances | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L417), [`../../modules/compute/main.tf`](../../modules/compute/main.tf#L208) |
| Database | RDS PostgreSQL | 1 instance, `db.t3.micro`, Single-AZ, gp3 20 GiB | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L250), [`../../modules/database/main.tf`](../../modules/database/main.tf#L35) |
| Object storage | S3 frontend + API artifact tùy chọn | 1 private frontend bucket; artifact bucket chỉ là dependency bên ngoài nếu được truyền vào compute | [`../../modules/frontend/main.tf`](../../modules/frontend/main.tf#L24), [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L466) |
| CDN | CloudFront | 1 distribution, S3 origin + ALB origin, `PriceClass_100` | [`../../modules/frontend/main.tf`](../../modules/frontend/main.tf#L90), [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L223) |
| Monitoring | CloudWatch | 2 log groups, 1 metric filter, 7 standard metric alarms | [`../../modules/monitoring/main.tf`](../../modules/monitoring/main.tf#L11), [`../../modules/monitoring/main.tf`](../../modules/monitoring/main.tf#L35) |
| Certificates | ACM | ALB public certificate; CloudFront certificate chỉ khi custom viewer domain bật | [`../../modules/certificates/main.tf`](../../modules/certificates/main.tf#L7) |

## 5. Cấu hình chi tiết theo service

### 5.1. Amazon EC2

Chọn service **Amazon EC2**. Calculator có thể tự chọn instance rẻ nhất như `t4g.nano`; không dùng lựa chọn tự động đó. Trong bảng instance, tìm `t3.micro` và chọn đúng dòng có 2 vCPU, 1 GiB memory, EBS only, On-Demand `$0.0104/hour` tại US East (N. Virginia).

#### EC2 specifications và workload

| Trường trong Calculator | Giá trị phải nhập | Đối chiếu Terraform |
|---|---|---|
| Location type | Region | Không chọn Local Zone/Wavelength |
| Region | US East (N. Virginia) / `us-east-1` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L18) |
| Tenancy | Shared Instances | Không chọn Dedicated Instance/Host |
| Operating system | Linux | AMI Linux được truyền từ environment |
| Workload | Constant usage | ASG chạy 24x7 theo baseline |
| Number of instances | `2` | Desired/min = 2; `max_size = 4` chỉ là scale-out limit |
| Instance family/type | Tìm và chọn `t3.micro` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L410) |
| Current generation | Bật **Show only current generation instances** nếu có | Giữ đúng `t3.micro` theo code |
| Expected usage | `100%` | Instance chạy 730 giờ/tháng |
| Usage type | `Utilization percent per month` | Không dùng Spot hoặc Savings Plan |
| Payment option | **On-Demand** | Không nhập Compute/EC2 Savings Plans |

Đối chiếu phần EC2 instance:

```text
Instance type: t3.micro
Hourly:       $0.0104
Instances:    2
Usage:        100%
Hours:        730/month
Formula:      2 × 730 × $0.0104 = $15.18/month
```

Trong form EBS bạn đã cung cấp, Calculator tính theo **storage của mỗi EC2 instance**. Với 2 instance chạy 730 giờ:

```text
1,460 total EC2 hours / 730 hours per month = 2.00 instance months
Storage for each EC2 instance: 20 GB
Snapshot Frequency: No snapshot storage
Billable storage basis: 20 GB × 2.00 instance months = 40 GB-month
```

Nếu ô **Storage amount** đang để trống hoặc bằng `0`, Calculator sẽ hiển thị **EBS Storage Cost: 0 USD** và **EBS total cost: 0.00 USD**. Giá trị đó chỉ phản ánh input EBS bằng 0, không phản ánh root volume `20 GiB` trong Terraform. Với cấu hình hiện tại phải nhập `20` và Unit `GB`; không nhập `40` vào ô **Storage for each EC2 instance**.

#### Các mục optional hiển thị trong form EC2

| Mục optional | Giá trị baseline cần nhập | Khi nào thay đổi |
|---|---|---|
| **Amazon Elastic Block Store (EBS)** | Mở phần này và nhập theo bảng chi tiết bên dưới | Đổi `compute_root_volume_size_gib` hoặc số instance chạy thường xuyên |
| EBS provisioned IOPS/throughput | Theo đúng field `gp3 - IOPS` và `gp3 - Throughput` bên dưới | Chỉ tăng khi provision vượt baseline |
| **Detailed monitoring** | `No` / `0`; `compute_detailed_monitoring = false` | Bật khi đổi variable này thành `true` |
| **Data transfer** | `0` trong fixed-cost baseline | Nhập GB internet/inter-Region theo traffic thực tế; không cộng lại traffic đã tính ở CloudFront/ALB |
| **Additional costs** | `0` trong baseline | Thêm CPU credits hoặc chi phí khác chỉ khi workload/account thực tế phát sinh |

AWS có thể hiển thị ghi chú rằng usage dưới 100% làm Calculator giả định instance không chạy liên tục và volume có thể bị xóa. Repository giữ root volume provisioned, nên baseline phải dùng `100%`; volume còn tồn tại vẫn có thể bị tính phí dù instance stopped.

> Lưu ý: T3 có thể phát sinh CPU credit nếu workload vượt baseline. Calculator cần thêm CPU-credit usage nếu workload thực tế dùng Unlimited vượt baseline.

### 5.2. Amazon EBS

Đây là service/component **optional** trong form EC2. Khuyến nghị nhập tại **Amazon Elastic Block Store (EBS) - optional** bên trong EC2; chỉ chọn service **Amazon EBS** riêng nếu estimate không bao gồm attached storage.

| Tên field đúng trong Calculator | Value/Unit cần nhập | Thông tin đối chiếu |
|---|---|---|
| **Storage for each EC2 instance** | `20` | Dung lượng root EBS của một instance |
| **Choose EBS volume storage type** | `General Purpose SSD (gp3)` | Khớp `volume_type = "gp3"` |
| **General Purpose SSD (gp3) - IOPS** | Value: `3,000`; Unit: `IOPS` | gp3 baseline; UI có thể ghi max 80,000 IOPS/volume |
| **General Purpose SSD (gp3) - Throughput** | Value: `125`; Unit: `MBps` | gp3 baseline; UI có thể ghi max 2,000 MBps/volume |
| **Storage amount** | Value: `20`; Unit: `GB` | Đây là storage cho mỗi EC2 instance, không phải tổng 40 GB |
| **Snapshot Frequency** | `No snapshot storage` | Repository không tạo snapshot resource |

Công thức theo cách Calculator hiển thị: `20 GB/instance × 2.00 instance months × giá gp3/GB-month`.

### 5.3. Elastic Load Balancing

Chọn **Elastic Load Balancing → Application Load Balancer**:

| Ô nhập | Giá trị baseline |
|---|---|
| Load balancers | 1 |
| Hours | 730 |
| Average LCU | Khoảng 0.1 LCU, suy ra từ các dimension nhỏ bên dưới |
| New connections, active connections, processed bytes, rule evaluations | Nhập các dimension bên dưới; Calculator lấy dimension cao nhất để tính LCU |

Công thức baseline US East: `730 × ($0.0225 + 0.1 × $0.008) = $17.01/tháng`. AWS tính ALB theo giờ chạy và LCU usage; giá LCU phụ thuộc dimension cao nhất, không phải tổng các dimension. [Nguồn ALB pricing](https://aws.amazon.com/elasticloadbalancing/pricing/).

#### Giả định LCU nhỏ nhưng thông thường

Đây là usage assumption để nhập Calculator, không phải giá trị suy ra từ HCL. Các giá trị được chọn cho một API ecommerce dev nhỏ, chạy ổn định, không có Lambda target:

| Field đúng trong Calculator | Giá trị nhập | Cách hiểu |
|---|---:|---|
| **Processed bytes (Lambda functions as targets)** | `0` GB/hour | Repository không dùng Lambda làm ALB target |
| **Processed bytes (EC2 Instances and IP addresses as targets)** | `0.1` GB/hour | Khoảng 100 MB dữ liệu qua ALB mỗi giờ |
| **Average number of new connections per ALB** | `1`/second | Tải nhỏ, trung bình 1 connection mới mỗi giây |
| **Average connection duration** | `1` second | Dùng mức tối thiểu mà Calculator yêu cầu nếu connection ngắn |
| **Average number of requests per second per ALB** | `2` requests/connection | Trung bình 2 request cho mỗi connection |
| **Average number of rule evaluations per request** | `1` | ALB có một listener rule cho API/header |

Với giả định trên, dimension cao nhất là processed bytes khoảng `0.1 LCU`; các dimension còn lại thấp hơn. Nếu Calculator yêu cầu thêm field active connections, dùng `1` active connection trung bình (`1 new connection/second × 1 second duration`). Nếu có access log/CloudWatch metric thực tế, thay assumption bằng số đo thực tế.

#### Đối chiếu các thành phần ALB

| Thành phần trong Calculator | Giá trị cần nhập/đối chiếu | Evidence |
|---|---|---|
| Load balancer type | Application Load Balancer | [`../../modules/alb/main.tf`](../../modules/alb/main.tf#L3) |
| Scheme | Internet-facing | [`../../modules/alb/main.tf`](../../modules/alb/main.tf#L5) |
| Load balancers | `1` | Module chỉ có một `aws_lb` |
| Availability Zones | `2` public subnets | [`../../environments/dev/main.tf`](../../environments/dev/main.tf#L81) |
| Hours | `730`/tháng | Chạy 24x7 theo baseline |
| LCU usage | Khoảng `0.1` average LCU theo assumption nhỏ ở trên | Thay bằng 4 dimension thực tế nếu có metrics |
| New connections | `1`/second | Usage assumption, không phải Terraform input |
| Active connections | `1` connection trung bình | Từ 1 new connection/second × 1 second |
| Processed bytes | `0.1` GB/hour cho EC2/IP targets; Lambda = `0` | Chỉ tính payload đi qua ALB/API, không cộng static S3 traffic |
| Requests per connection | `2` | Usage assumption cho API |
| Rule evaluations per request | `1` | ALB có listener rule cho `/api` và header CloudFront |
| Listener/TLS | HTTPS port `443`, TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06` | [`../../modules/alb/main.tf`](../../modules/alb/main.tf#L50), [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L94) |
| Target group | HTTP tới API port `3000`, 1 target group | [`../../modules/alb/main.tf`](../../modules/alb/main.tf#L22), [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L108) |

Target group, listener và listener rule không tạo thêm ALB line item. Dev dùng HTTP origin nên không tạo regional ALB certificate; production HTTPS certificate là mô hình riêng.

### 5.4. Amazon RDS for PostgreSQL

Chọn **Amazon RDS for PostgreSQL**. Form có nhiều nhóm component; nhập theo đúng thứ tự dưới đây. Trong ví dụ bạn gửi, Calculator đang hiển thị `gp2` và `100 GB`, nhưng đó **không phải cấu hình của repository**. Với code hiện tại phải đổi thành `gp3` và `20 GB`.

#### PostgreSQL instance specifications

| Tên field đúng trong Calculator | Value cần nhập | Đối chiếu Terraform |
|---|---:|---|
| Description | `dev-rds-postgresql` | Tên mô tả estimate, không ảnh hưởng cấu hình AWS |
| Choose a location type | `Region` | Không chọn Local Zone |
| Region | `US East (N. Virginia)` / `us-east-1` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L18) |
| Nodes | `1` | Module chỉ tạo một `aws_db_instance` |
| Selected instance | `db.t3.micro` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L264) |
| Utilization (On-Demand only) - Value | `100` | Chạy 24x7; không dùng utilization để giả định instance tự stop |
| Utilization - Unit | `%Utilized/Month` | Đúng unit trong Calculator |
| Deployment Option | `Single-AZ` | `multi_az = false`; [`../../modules/database/main.tf`](../../modules/database/main.tf#L50) |
| Pricing Model | `OnDemand` | Không dùng Reserved/Reserved DB instance |

#### RDS Proxy

| Tên field | Value cần nhập | Lý do |
|---|---|---|
| Would you be creating an RDS Proxy with the database? | `No` | Repository không tạo `aws_db_proxy` hoặc target proxy |

#### Storage

| Tên field đúng trong Calculator | Value/Unit cần nhập | Đối chiếu Terraform |
|---|---|---|
| Storage volume | `General Purpose SSD (gp3)` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L285) |
| Storage amount | Value: `20`; Unit: `GB` | `allocated_storage = 20`; [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L271) |
| Maximum storage | Không nhập vào ô Storage amount | `100 GiB` chỉ là `max_allocated_storage`, giới hạn autoscaling; [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L278) |
| Provisioned IOPS/throughput | Baseline/không provision thêm | Repository không cấu hình IOPS hoặc throughput riêng |

#### CloudWatch Database Insights Pricing for RDS Provisioned Instances

| Tên field | Value cần nhập | Lý do |
|---|---|---|
| Would you be enabling Database Insights with the database? | `No` | Repository không cấu hình Database Insights |

#### RDS Extended Support

| Tên field | Value cần nhập | Lý do |
|---|---|---|
| Do you plan on running an Extended Support major version? | `No` | Repository dùng PostgreSQL `16.4`, không có yêu cầu Extended Support |
| Pricing year | Không nhập | Chỉ xuất hiện khi chọn `Yes` |
| Number of hours running on RDS Extended Support | `0` | Không có Extended Support trong baseline |

#### Backup Storage

| Tên field | Value cần nhập | Lý do |
|---|---:|---|
| Additional backup storage | `0` GB trong baseline | Chưa có số liệu backup vượt allowance; backup retention của Terraform là 7 ngày |
| Backup retention | `7` ngày | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L326) |

#### Snapshot Export và read replicas

| Tên field/component | Value cần nhập | Lý do |
|---|---:|---|
| Total Size of Backup Processed for Export (GB) | `0` GB/month | `database_skip_final_snapshot = true`; [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L340) |
| Read replicas | `0` | Không có resource read replica |
| Multi-AZ standby | `0` | Deployment là Single-AZ |

`database_skip_final_snapshot = true`, nên không đưa final snapshot export vào baseline. CloudWatch log exports cũng là `[]`, Performance Insights/Enhanced Monitoring và RDS Proxy không được cấu hình. Các chi tiết này không được âm thầm chuyển thành `Yes` chỉ vì Calculator hiển thị component đó.

Công thức: `730 × giá db.t3.micro/giờ + 20 × giá RDS gp3/GB-month + backup bổ sung + snapshot export + transfer/I/O nếu có`.

> Không hard-code giá RDS vào HCL. RDS pricing thay đổi theo engine, Region, deployment option, storage và version hỗ trợ; lấy giá hiển thị tại thời điểm tạo estimate trong Calculator.

### 5.5. Amazon S3

Chọn service **Amazon Simple Storage Service (S3)**. Trong Calculator, chỉ chọn storage class/feature mà repository thực sự dùng.

#### Select S3 Storage classes and other features

| Tên lựa chọn trong Calculator | Trạng thái cần chọn | Lý do đối chiếu |
|---|---|---|
| S3 Standard | **Chọn** | Frontend bucket dùng S3 Standard |
| S3 Intelligent-Tiering | Không chọn | Không có Terraform configuration |
| S3 Standard - Infrequent Access | Không chọn | Không có Terraform configuration |
| S3 Glacier Flexible Retrieval | Không chọn | Không có Terraform configuration |
| S3 Glacier Deep Archive | Không chọn | Không có Terraform configuration |
| S3 Management and Insights | Không chọn | Không tạo Inventory/Storage Lens/analytics resource |
| S3 One Zone - Infrequent Access | Không chọn | Không có Terraform configuration |
| S3 Vectors | Không chọn | Không có resource tương ứng |
| S3 Object Lambda | Không chọn | Không có Lambda/Object Lambda |
| S3 Glacier Instant Retrieval | Không chọn | Không có Terraform configuration |
| Data Transfer | Không chọn riêng | S3 → CloudFront origin transfer không phải S3 direct Internet egress |
| S3 Express One Zone | Không chọn | Không có resource tương ứng |
| S3 Access Grants | Không chọn | Không có resource tương ứng |
| S3 Files | Không chọn | Không có file interface |
| S3 Tables | Không chọn | Không có table resource |

#### S3 Standard feature

| Tên field đúng trong Calculator | Value/Unit cần nhập | Evidence/giải thích |
|---|---|---|
| Region | `US East (N. Virginia)` / `us-east-1` | Region của frontend bucket |
| S3 Standard storage | Value: `5`; Unit: `GB per month` | Baseline cho 1 private frontend bucket |
| How will data be moved into S3 Standard? | **The specified amount of data is already stored in S3 Standard** | Đang tính recurring monthly cost, không tính initial migration |
| PUT, COPY, POST, LIST requests to S3 Standard | Value: `1,000`; Unit: requests/month | Assumption nhỏ cho frontend deployment/upload; HCL không chứa request count |
| GET, SELECT, and all other requests from S3 Standard | Value: `1,000,000`; Unit: requests/month | Assumption nhỏ; tương đương khoảng 10% origin requests nếu CloudFront có 10M viewer requests và 90% cache hit |
| Data returned by S3 Select | Value: `0`; Unit: `GB per month` | Repository không dùng S3 Select |
| Data scanned by S3 Select | Value: `0`; Unit: `GB per month` | Repository không dùng S3 Select |

Các số `5 GB`, `1,000 PUT/LIST` và `1,000,000 GET` là **baseline assumption để bạn nhập**, không thể suy ra chính xác từ HCL. Khi có access log/CI metrics, thay chúng bằng số liệu thực tế. AWS mô tả S3 pricing theo storage, requests, retrieval, data transfer và các feature; xem [S3 pricing](https://aws.amazon.com/s3/pricing/).

#### Các component S3 tiếp theo trong Calculator

| Component | Value baseline | Cách xử lý |
|---|---:|---|
| Data retrieval | `0` | S3 Standard không dùng retrieval feature riêng trong baseline |
| Data transfer out to Internet | `0 GB/month` | Frontend được phục vụ qua CloudFront OAC; không truy cập public S3 |
| Data transfer to CloudFront | `0 GB/month` | Không cộng S3 internet egress cho S3 → CloudFront |
| Transfer Acceleration | `0` | Repository không cấu hình |
| Replication, Inventory, Analytics, Batch Operations | `0` | Không có resource tương ứng |
| Versioned object storage | Tính theo dung lượng của mọi version | Bucket bật versioning; cộng thêm nếu giữ nhiều bản build |

API artifact là một trường hợp riêng: `application_artifact_bucket` mặc định là `null`. Khi để `null`, bootstrap không tải ZIP từ S3. Nếu truyền tên bucket, đó là dependency bên ngoài module compute; hãy thêm storage, PUT/GET và data transfer của bucket đó vào service S3. Không tính bucket artifact vào baseline nếu chưa xác định bucket đó do account này sở hữu.

### 5.6. Amazon CloudFront

Chọn service **Amazon CloudFront**. Màn hình đầu tiên có hai lựa chọn: **Flat Rate** và **Pay as you go**. Với repository hiện tại, chọn **Pay as you go**.

#### Thông tin chung và lựa chọn pricing model

| Tên field/section đúng trong Calculator | Giá trị cần chọn/nhập | Lý do |
|---|---|---|
| Description | `dev-cloudfront` | Tên nhận diện estimate, không ảnh hưởng resource |
| Choose a location type | `Region` | CloudFront là dịch vụ global nhưng Calculator vẫn yêu cầu location |
| Region | `US East (N. Virginia)` / `us-east-1` | Region dùng cho estimate; [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L18) |
| Pricing model | **Pay as you go** | Khớp distribution hiện tại; không chọn Flat Rate |

Không chọn **Flat Rate** cho baseline. Flat Rate gộp CloudFront với nhiều dịch vụ/tính năng như CDN, WAF, DDoS protection, DNS, logging, serverless edge compute và S3 Standard credits. Repository hiện tại không triển khai một flat-rate plan; chọn nhầm plan sẽ làm cost model không còn phản ánh riêng các resource Terraform.

Các lựa chọn Flat Rate đang hiển thị trong Calculator — **không chọn**:

| CloudFront Flat-Rate Plan | Trạng thái |
|---|---|
| Free Plan | Không chọn |
| Pro Plan | Không chọn |
| Business Plan | Không chọn |
| Premium Plan | Không chọn |
| Premium (750M / 75TB) Plan | Không chọn |
| Premium (1.25B / 125TB) Plan | Không chọn |
| Premium (2B / 200TB) Plan | Không chọn |
| Premium (3.5B / 350TB) Plan | Không chọn |
| Premium (6B / 600TB) Plan | Không chọn |

#### CloudFront Edge Locations

Sau khi chọn **Pay as you go**, nhập theo từng geography. Baseline nhỏ dưới đây chỉ chọn **United States**; các geography còn lại để `0`/không nhập vì chưa có traffic distribution thực tế.

| Tên section/field đúng trong Calculator | United States - giá trị nhập | Cách nhập |
|---|---:|---|
| CloudFront Edge Locations → United States | Chọn/mở section | Section này cũng bao gồm Edge locations ở Mexico |
| Data transfer out to internet | `100` GB per month | Nhập tổng gross traffic viewer giả định trước miễn phí |
| Data transfer out to origin | `0` GB per month | Baseline không giả định POST/PUT body lớn; thay bằng API upload traffic thực tế |
| Number of requests (HTTPS) | `10,000,000` per month | Nhập tổng gross HTTPS viewer requests giả định trước miễn phí |
| Canada | `0` | Không chọn/không nhập trong baseline |
| Asia Pacific | `0` | Không chọn/không nhập trong baseline |
| Australia | `0` | Không chọn/không nhập trong baseline |
| Europe | `0` | Không chọn/không nhập trong baseline |
| India | `0` | Không chọn/không nhập trong baseline |
| Japan | `0` | Không chọn/không nhập trong baseline |
| Middle East | `0` | Không chọn/không nhập trong baseline |
| South Africa | `0` | Không chọn/không nhập trong baseline |
| South America | `0` | Không chọn/không nhập trong baseline |

Calculator hiển thị ghi chú **CloudFront 1TB Free Tier**: 1,024 GB data transfer out và 10 triệu HTTP/HTTPS requests đầu tiên mỗi tháng được miễn phí, đồng thời yêu cầu người dùng tự loại trừ khỏi input tính phí. Để tránh hiểu nhầm, dùng một trong hai cách sau và ghi rõ trong estimate:

| Cách lập estimate | Data transfer out to internet nhập vào | HTTPS requests nhập vào | Mục đích |
|---|---:|---:|---|
| **Baseline theo đúng form bạn gửi** | `100 GB/month` gross | `10,000,000/month` gross | Calculator hiển thị/đối chiếu usage; phải manually exclude phần miễn phí khi xem cost |
| **Cost-only sau khi trừ allowance** | `0 GB/month` billable | `0/month` billable | Không dùng để mô tả traffic thực tế; chỉ dùng để kiểm tra phần chargeable |

Khuyến nghị lưu estimate với cách **Baseline theo đúng form bạn gửi**, sau đó xem **Show calculations** và ghi lại phần được loại trừ. Không nhập `1,024 GB` hoặc `10,000,000` lần nữa vào một line item khác. AWS cũng ghi rõ CloudFront tính theo data transfer out, HTTP/HTTPS requests, geography và feature; xem [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/).

#### Giá trị baseline và các component CloudFront khác

| Ô nhập/component | Giá trị baseline | Đối chiếu Terraform |
|---|---|---|
| Distributions | `1` | [`../../modules/frontend/main.tf`](../../modules/frontend/main.tf#L90) |
| Price class | `PriceClass_100` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L223) |
| Data transfer out to viewers | `100 GB/month` gross ở United States | Usage assumption |
| Data transfer out to origin | `0 GB/month` baseline | Thay bằng data transfer của POST/PUT/API thực tế |
| Number of requests (HTTPS) | `10,000,000/month` gross ở United States | Usage assumption |
| Discounted Pricing | Không chọn discount/commitment trong baseline | Không có Savings Bundle hoặc custom commitment trong Terraform |
| S3 origin requests/data transfer | Không nhập thêm trong CloudFront viewer fields | Private S3 origin dùng OAC; origin fetch cần tránh cộng trùng |
| ALB origin requests/data transfer | Đã phản ánh bằng API traffic/ALB LCU; không cộng viewer traffic lần nữa | `/api/*` dùng ALB origin, dev origin protocol `http-only` |
| Origin Shield | `0` | Repository không cấu hình |
| Invalidations | `0` baseline | Nhập số path thực tế nếu có deployment invalidation |
| CloudFront Functions/Lambda@Edge | `0` | Không có resource tương ứng |
| Custom viewer alias/certificate | `0` trong baseline | `enable_custom_viewer_domain = false`; chỉ thêm ở future improvement |

`PriceClass_100` là cấu hình distribution, còn các giá trị data transfer/request là usage input. Hai khái niệm này không thay thế cho nhau. CloudFront origin fetch từ AWS origin và CloudFront viewer delivery cũng là hai chiều traffic khác nhau; không cộng cùng một GB vào cả S3, ALB và CloudFront.

Trong baseline, không nhập domain mặc định `*.cloudfront.net` thành Route 53 record hoặc ACM certificate. Certificate mặc định của CloudFront phục vụ **Client → CloudFront**; dev dùng HTTP cho **CloudFront → ALB** và không tạo regional ALB certificate. Production HTTPS là mô hình cost riêng.

### 5.7. Amazon CloudWatch

Chọn **Amazon CloudWatch**. Màn hình này ghi rõ các calculation bên dưới chưa loại trừ Free Tier; vì vậy cần nhập usage gross, sau đó kiểm tra phần allowance trong **Show calculations**.

#### Thông tin chung

| Tên field đúng trong Calculator | Giá trị cần chọn/nhập | Evidence/giải thích |
|---|---:|---|
| Description | `dev-cloudwatch` | Tên nhận diện estimate |
| Choose a location type | `Region` | CloudWatch resources của environment là regional |
| Region | `US East (N. Virginia)` / `us-east-1` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L18) |

#### Metrics

| Tên field đúng trong Calculator | Giá trị nhập | Unit/cách hiểu | Evidence |
|---|---:|---|---|
| Number of Metrics (includes detailed and custom metrics) | **`7`** | Metrics | Giá trị baseline của estimate; không đồng nhất với số alarm |
| Detailed monitoring metrics | `0` additional | Vì `compute_detailed_monitoring = false` | [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L424) |
| Custom metrics được code tạo/đẩy | `5` series steady-state | `mem_used_percent` + `used_percent` trên 2 EC2 = 4, cộng `ApplicationErrors` = 5 | [`../../modules/compute/main.tf`](../../modules/compute/main.tf#L30), [`../../modules/monitoring/main.tf`](../../modules/monitoring/main.tf#L162) |

`7` là giá trị cần nhập cho estimate baseline hiện tại theo form bạn cung cấp. HCL chứng minh được tối thiểu 5 custom metric series steady-state; HCL không chứng minh được 2 metric còn lại nếu chưa có metric inventory/runtime. Do đó không dùng số `7` để khẳng định repository đang phát sinh đúng 7 custom metrics. Nếu mục tiêu là cost model chỉ bám metric custom đã chứng minh bằng code, dùng `5` và ghi lý do trong estimate.

#### APIs

Nhập số request **mỗi tháng**. Không có code gọi `GetMetricData` hoặc `GetMetricWidgetImage`; CloudWatch Agent có thể phát sinh `PutMetricData`, nhưng số request phụ thuộc batching/runtime nên phải ghi là assumption.

| Tên field đúng trong Calculator | Giá trị baseline | Unit |
|---|---:|---|
| GetMetricData: Number of metrics requested | `0` | requests/month |
| GetMetricWidgetImage: Number of metrics requested | `0` | requests/month |
| Number of other API requests | `87,600` | requests/month |

`87,600` được tính theo assumption thận trọng: `2 EC2 instances × 1 PutMetricData request/phút × 60 × 730 giờ`. Nếu CloudWatch Agent gom nhiều metric vào một request hoặc thực tế có dashboard/API query, thay bằng số đo từ account; không lấy `7 alarms` làm API request count.

#### Database Insights Pricing for Aurora and RDS Provisioned Instances

| Tên field đúng trong Calculator | Giá trị nhập | Unit | Lý do |
|---|---:|---|---|
| Number of vCPUs monitored by Database Insights | `0` | per hour | Database Insights đang tắt |

Không bật Database Insights trong RDS Calculator. Repository chỉ tạo RDS PostgreSQL `db.t3.micro`, nhưng không bật Database Insights; không đưa vCPU của RDS vào field này.

#### Database Insights Pricing for Aurora Serverless v2 Instances

| Tên field đúng trong Calculator | Giá trị nhập | Unit |
|---|---:|---|
| Number of Aurora Capacity Units (ACUs) monitored by Database Insights | `0` | per hour |

Repository không dùng Aurora Serverless v2.

#### Database Insights Pricing for Aurora Limitless Databases

| Tên field đúng trong Calculator | Giá trị nhập | Unit |
|---|---:|---|
| Number of Aurora Capacity Units (ACUs) monitored by Database Insights | `0` | per hour |

Repository không dùng Aurora Limitless Database.

#### Logs

Mở section **Logs**. Nhập theo đúng thứ tự form bạn cung cấp:

| Tên field đúng trong Calculator | Giá trị nhập | Unit/cách nhập | Evidence/giải thích |
|---|---:|---|---|
| Standard Logs: Data Ingested | **`2`** | `GB` | Baseline input bạn đã cung cấp cho API + system logs |
| Infrequent Access Logs: Data Ingested | `0` | `GB` | Không cấu hình Infrequent Access log group |
| Standard Logs Delivered to CloudWatch Logs | `0` | `GB` | Không có vended log source; API/system logs được gửi trực tiếp vào Standard Logs |
| Infrequent Access Logs Delivered to CloudWatch Logs | `0` | `GB` | Không có vended Infrequent Access logs |
| Log Storage/Archival: Yes to Store Logs | **`Yes`** | Chọn lưu logs | Form đang tính archival/storage |
| Log Storage/Archival retention | **`1 month`** | `1` month | Đây là giả định mặc định được form hiển thị: “Assuming 1 month retention” |
| Logs Delivered to S3: Data Ingested | `0` | `GB` | Repository không cấu hình CloudWatch Logs delivery tới S3 |
| Logs Delivered to S3: Format Converted to Apache Parquet | **`Disabled`** | Không bật | Không có VPC Flow Logs/Global Accelerator flow logs delivery |

Repository thực tế tạo 2 log groups API và system, retention Terraform là 14 ngày: [`../../modules/monitoring/main.tf`](../../modules/monitoring/main.tf#L11), [`../../modules/monitoring/main.tf`](../../modules/monitoring/main.tf#L22), [`../../environments/dev/variables.tf`](../../environments/dev/variables.tf#L495). Vì form bạn cung cấp đang dùng `Yes / 1 month`, tài liệu ghi đây là **Calculator storage assumption**, không khẳng định retention runtime đã đổi thành 1 tháng. Nếu muốn cost model khớp tuyệt đối với Terraform, cần thay giá trị storage/retention theo cách Calculator cho phép nhập 14 ngày.

#### Logs Insights Queries (Analyse Log Data)

| Tên field/component | Giá trị nhập | Unit |
|---|---:|---|
| Expected Logs Data scanned | `0` | `GB` |

Không tính việc mở log group trong Console là một query định kỳ. Chỉ thay `0` khi có query vận hành thực tế và biết tổng GB dữ liệu được scan.

#### Dashboards and Alarms

| Tên field/component | Giá trị nhập | Lý do/evidence |
|---|---:|---|
| Number of Dashboards | `0` | Repository không tạo `aws_cloudwatch_dashboard` |
| Number of Standard Resolution Alarm Metrics | `7` | 2 ALB + 2 ASG + 2 RDS + 1 API error alarm; [`../../modules/monitoring/main.tf`](../../modules/monitoring/main.tf#L35) |
| Number of High Resolution Alarm Metrics | `0` | Các alarm dùng period từ 60 giây trở lên |
| Number of composite alarms | `0` | Không tạo composite alarm |
| Number of alarms defined with a Metrics Insights query | `0` | Không dùng Metrics Insights query |
| Average number of metrics scanned by each Metrics Insights query | `0` | Không có Metrics Insights query |

Bảy alarm là: `alb_5xx`, `alb_unhealthy_hosts`, `asg_cpu`, `asg_in_service`, `rds_cpu`, `rds_free_storage`, `api_errors`. Số alarm metric này không được cộng lại vào **Number of Metrics** nếu Calculator đã tách hai field; không nhập `7` thêm lần nữa ở Metrics chỉ vì có 7 alarm. `alarm_actions` rỗng chỉ ảnh hưởng notification, không làm giảm số alarm metric.

#### Canaries

Calculator không cho phép **Number of Canary runs** nhỏ hơn `1` khi section này được kích hoạt. Repository không tạo CloudWatch Synthetics canary, vì vậy baseline phải để component này **Not configured/không thêm vào estimate**, không nhập `0` vào một field đang active.

Nếu UI bắt buộc phải nhập sau khi bạn đã mở component, giá trị kỹ thuật tối thiểu là:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi section active | Unit | Cách xử lý cost model |
|---|---:|---|---|
| Number of Canary runs | `1` | runs/month | Chỉ là UI minimum; không coi là canary được Terraform triển khai |

Với `1` run, Calculator có thể hiển thị `0.00 USD` do Free Tier, nhưng vẫn phải ghi chú đây là giá trị để vượt validation của UI, không phải usage thực tế.

#### Contributor Insights for CloudWatch Logs

Calculator không cho phép các field đang active nhỏ hơn `1`: số rule tối thiểu là `1`, số matched events tối thiểu là `1 million/month`. Repository không tạo Contributor Insights rule, vì vậy baseline phải để component này **Not configured/không thêm vào estimate**, không nhập `0` vào section đang active.

Nếu UI bắt buộc phải nhập sau khi đã mở component, giá trị tối thiểu là:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi section active | Unit |
|---|---:|---|
| Number of Contributor Insights rules for CloudWatch | `1` | rules |
| Total number of matched log events for CloudWatch | `1` | million matched log events/month |

Đây chỉ là UI minimum để vượt validation; không đưa khoản này vào baseline cost nếu feature không tồn tại trong Terraform.

#### Contributor Insights for DynamoDB

Calculator không cho phép các field đang active nhỏ hơn `1`: số rule tối thiểu là `1`, số event tối thiểu là `1 million/month`. Repository không tạo DynamoDB hoặc Contributor Insights rule, vì vậy baseline phải để component này **Not configured/không thêm vào estimate**.

Nếu UI bắt buộc phải nhập sau khi đã mở component, giá trị tối thiểu là:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi section active | Unit |
|---|---:|---|
| Number of Contributor Insights rules for DynamoDB | `1` | rules |
| Total number of events for DynamoDB | `1` | million events/month |

Không dùng các giá trị tối thiểu này để khẳng định repository có DynamoDB hoặc Contributor Insights.

#### Lambda Insights

Calculator không cho phép các field đang active nhỏ hơn `1`: số Lambda function tối thiểu là `1`, số request mỗi function tối thiểu là `1` theo validation của UI. Repository không tạo Lambda function, vì vậy baseline phải để component này **Not configured/không thêm vào estimate**.

Nếu UI bắt buộc phải nhập sau khi đã mở component, nhập:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi section active | Unit/cảnh báo |
|---|---:|---|
| Number of Lambda functions | `1` | functions |
| Number of requests per function | `1` | UI hiển thị `per hour`, nhưng validation ghi tối thiểu `1 per month`; giữ đúng unit mà Calculator đang hiển thị |

Repository không tạo Lambda function.

#### RUM

Calculator không cho phép web RUM visits nhỏ hơn `1` hoặc web sampling rate nhỏ hơn `1%` khi phần web RUM đang active. Repository không có RUM application, vì vậy baseline nên để RUM **Not configured/không thêm vào estimate**.

Nếu UI bắt buộc phải nhập phần web RUM:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi section active | Unit |
|---|---:|---|
| Monthly visits to your web application | `1` | visits/month |
| Number of web RUM events per visit | `0` | events/visit; form bạn gửi không báo lỗi với `0` |
| Web sampling rate | `1` | `%` |

Các field mobile theo form bạn paste:

| Tên field đúng trong Calculator | Giá trị nhập theo form | Ghi chú |
|---|---:|---|
| Monthly visits to your mobile applications | `0` | Không có mobile RUM usage baseline |
| Number of users or sessions visiting your mobile app per month | `0` | Không có mobile session baseline |
| Number of mobile OTEL events and spans or spans per visit | `70` | Giữ đúng giá trị bạn cung cấp |
| Mobile sampling rate | `100`% | Giữ đúng giá trị bạn cung cấp |

Repository không có RUM application. Giá trị `70` events/spans per visit và `100%` mobile sampling được giữ đúng theo form bạn paste, nhưng mobile visits đang là `0`, nên không phát sinh RUM usage trong baseline. Nếu không chủ động estimate RUM, để section RUM **Not configured**; không nhập `0` vào các field web đang active vì Calculator sẽ báo validation error.

#### Internet Monitor

Calculator không cho phép số monitored resources hoặc city-networks nhỏ hơn `1`/giờ khi monitor đang active. Repository không tạo Internet Monitor, vì vậy baseline phải để component này **Not configured/không thêm vào estimate**.

Nếu UI bắt buộc phải nhập sau khi đã mở một monitor:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi monitor active | Unit |
|---|---:|---|
| Number of monitored resources | `1` | per hour |
| Number of city-networks to be monitored | `1` | per hour |

Không tạo Internet Monitor; không nhầm với CloudFront Edge Locations.

#### Application Signals

Calculator không cho phép các field active nhỏ hơn `1`: incoming requests và outgoing dependency requests tối thiểu `1`/tháng theo validation của UI, SLO tối thiểu `1`, và SLI metric period tối thiểu `1` phút. Repository không cấu hình Application Signals, vì vậy baseline phải để component này **Not configured/không thêm vào estimate**.

Nếu UI bắt buộc phải nhập sau khi đã mở component:

| Tên field đúng trong Calculator | Giá trị tối thiểu khi component active | Unit/cảnh báo |
|---|---:|---|
| Volume of incoming requests | `1` | UI hiển thị `per minute`, validation ghi tối thiểu `1 per month` |
| Volume of outgoing requests to dependencies | `1` | UI hiển thị `per minute`, validation ghi tối thiểu `1 per month` |
| Number of Service level objectives (SLO) | `1` | SLO |
| Service level indicator metric period (minutes) | `1` | minutes |

#### Transaction Search & Application Signals

| Tên field/component | Giá trị nhập |
|---|---:|
| Application Signals: Data Ingested | `0` GB |
| Number of spans indexed as X-Ray trace summaries | `0` spans/month |

Không cấu hình OpenTelemetry/Application Signals/transaction search trong repository.

CloudWatch tính phí theo usage và Region; một số AWS service metrics, alarms, logs và API calls có Free Tier riêng. Vì vậy phải lưu cả input gross và kết quả sau allowance trong **Show calculations**. Xem [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/).

### 5.8. Amazon Virtual Private Cloud (VPC)

Chọn service **Amazon Virtual Private Cloud (VPC)**. Calculator hiển thị danh sách các VPC service/feature có thể tính phí. Với repository hiện tại, chỉ chọn **Public IPv4 Address**; VPC, subnet, route table và Internet Gateway không có line item tính phí riêng trong baseline.

#### Select VPC service(s) that you want to estimate

| VPC service/feature trong Calculator | Trạng thái baseline | Cách xử lý |
|---|---|---|
| VPN Connection | Không chọn | Không có Site-to-Site VPN resource |
| Network Access Analyzer | Không chọn | Không cấu hình |
| Reachability Analyzer | Không chọn | Không cấu hình |
| Traffic Mirroring | Không chọn | Không cấu hình |
| **Public IPv4 Address** | **Chọn** | Có public IP cho EC2 và internet-facing ALB |
| IPAM | Không chọn | Không cấu hình IP Address Manager |
| Data Transfer | Không chọn riêng | Không có số liệu VPC-only; tránh cộng trùng với CloudFront/ALB |
| VPC Route Server | Không chọn | Không cấu hình |
| Network Address Translation (NAT) Gateway | Không chọn | Kiến trúc hiện tại không dùng NAT Gateway |
| Transit Gateway | Không chọn | Không cấu hình |
| AWS PrivateLink | Không chọn | Không có endpoint/service endpoint |
| Gateway Load Balancer | Không chọn | Không cấu hình |
| Cloud WAN | Không chọn | Không cấu hình |

#### Public IPv4 Address feature

Sau khi chọn **Public IPv4 Address**, Calculator mở form **Public IPv4 Address feature**. Form này chỉ yêu cầu số lượng địa chỉ đang sử dụng và địa chỉ nhàn rỗi; không nhập số giờ vào một field riêng.

| Tên field đúng trong Calculator | Giá trị baseline | Unit/cách hiểu |
|---|---:|---|
| Number of In-use public IPv4 addresses | **`4`** | Public IPv4 addresses |
| Number of Idle public IPv4 addresses | **`0`** | Public IPv4 addresses |

#### Đối chiếu số lượng địa chỉ

| Resource | Số public IPv4 baseline | Evidence |
|---|---:|---|
| EC2 steady-state | `2` | Public subnets có `map_public_ip_on_launch = true`; [`../../modules/network/main.tf`](../../modules/network/main.tf#L45) |
| Internet-facing ALB trên 2 AZ | `2` | ALB dùng 2 public subnets; [`../../modules/alb/main.tf`](../../modules/alb/main.tf#L3), [`../../environments/dev/main.tf`](../../environments/dev/main.tf#L81) |
| RDS | `0` | `publicly_accessible = false`; [`../../modules/database/main.tf`](../../modules/database/main.tf#L50) |
| **Tổng In-use** | **`4`** | Chạy baseline 24x7 |

Không có idle address trong baseline vì repository không cấp phát public IPv4 rời rồi để không sử dụng. Calculator tự áp dụng thời gian pricing theo tháng; công thức tham khảo là `4 × 730 × giá public IPv4/giờ`. Giá thực tế cần lấy từ Calculator tại thời điểm estimate. [VPC pricing](https://aws.amazon.com/vpc/pricing/).

#### VPN Connection feature

Repository không tạo VPN. Vì vậy không chọn **VPN Connection** trong baseline. Nếu bạn chủ động estimate Site-to-Site VPN, Calculator yêu cầu mở **Site-to-Site VPN settings**:

| Tên field đúng trong Calculator | Baseline repository | Giá trị tối thiểu khi feature active | Unit |
|---|---|---:|---|
| Number of Site-to-Site VPN Connections | Không cấu hình | `1` | connections |
| Average duration for each connection | Không cấu hình | `24` | hours per day |

Không nhập `1` VPN chỉ để vượt validation nếu hệ thống thực tế không có VPN; giá trị đó sẽ làm estimate phát sinh chi phí không thuộc kiến trúc.

#### Client VPN settings

Repository cũng không tạo AWS Client VPN endpoint. Không chọn **Client VPN** trong baseline. Nếu feature active, các field trong form cần được nhập theo usage thật:

| Tên field đúng trong Calculator | Baseline repository | Giá trị tham khảo khi feature active | Unit |
|---|---|---:|---|
| Number of subnet associations | Không cấu hình | `1` | subnet associations |
| Number of active Client VPN connections (or users) | Không cấu hình | `1` nếu có một user/connection thực tế | connections/users |
| Average duration for each connection | Không cấu hình | `10` | hours per day |
| Working days per month | Không cấu hình | `22` | days/month |

Các giá trị `1 / 1 / 10 / 22` chỉ là giá trị tối thiểu/tham khảo khi Client VPN thật sự được sử dụng; không đưa vào baseline hiện tại.

#### VPC architecture đối chiếu từ Terraform

| Thành phần | Cấu hình repository | Evidence |
|---|---|---|
| VPC | `1` VPC, DNS support và DNS hostnames bật | [`../../modules/network/main.tf`](../../modules/network/main.tf#L22) |
| Internet Gateway | `1` IGW cho public route table | [`../../modules/network/main.tf`](../../modules/network/main.tf#L35) |
| Public subnets | `2`, có default route tới IGW | [`../../modules/network/main.tf`](../../modules/network/main.tf#L45), [`../../modules/network/main.tf`](../../modules/network/main.tf#L59) |
| Database subnets | `2`, route table không có default route | [`../../modules/network/main.tf`](../../modules/network/main.tf#L84), [`../../modules/network/main.tf`](../../modules/network/main.tf#L97) |
| NAT Gateway | `0` | [`../../modules/network/main.tf`](../../modules/network/main.tf#L96) |

Không cộng VPC/subnet/route table/IGW thành các service charge riêng. Chỉ đưa **Public IPv4 Address** vào estimate nếu Calculator hiển thị component này.

### 5.9. Route 53 và ACM

Baseline hiện tại:

- **Route 53 hosted zone:** không tính; custom viewer domain đang tắt và module không tạo hosted zone.
- **Route 53 record:** chỉ nhập khi thực tế dùng hosted zone cho DNS validation/origin domain.
- **ACM public certificate:** không có monthly charge cho public certificate non-exportable dùng với dịch vụ AWS tích hợp.
- **Custom viewer domain tương lai:** thêm hosted zone/query và certificate `us-east-1` nếu bật; không thay thế regional ALB certificate.

Nếu có 1 public hosted zone, công thức Route 53 tối thiểu là `$0.50/tháng + DNS queries`; giá domain registration là khoản riêng. [Nguồn Route 53 pricing](https://aws.amazon.com/route53/pricing/). ACM public certificate tích hợp không tính phí riêng. [Nguồn ACM pricing](https://aws.amazon.com/certificate-manager/pricing/).

### 5.10. Các resource không có line item riêng

| Resource | Cách ghi trong Calculator |
|---|---|
| VPC, subnet, route table, route association, Internet Gateway | `$0` direct service charge |
| Security groups và IAM role/policy | `$0` direct service charge |
| Auto Scaling Group | Không có phí ASG riêng; tính EC2 instances và CloudWatch liên quan |
| ALB target group/listener/rule | Đã nằm trong ALB; không cộng thành load balancer thứ hai |
| OAC, CloudFront behavior, ACM validation record | Không có line item riêng; chi phí nằm ở service/usage liên quan |
| NAT Gateway | Không có trong kiến trúc hiện tại; không nhập |
| SNS topic | Không do repository tạo; chỉ nhập nếu bên ngoài đã tạo và có usage |

## 6. Bảng đối chiếu sau khi nhập Calculator

Sau khi thêm service, kiểm tra các giá trị chính trong phần summary/detail của estimate. Nếu khác bảng này, trước tiên kiểm tra lại filter/usage assumption; không tự sửa HCL để làm khớp với Calculator.

| Line item cần thấy | Giá trị phải đối chiếu | Nguồn cấu hình | Cảnh báo khi đối chiếu |
|---|---|---|---|
| EC2 On-Demand | 2 × `t3.micro` × 730 giờ | `compute_desired_capacity = 2`; ASG min = 2 | Không nhập `max_size = 4` thành 4 instance chạy thường xuyên |
| EC2 EBS | Storage for each EC2 instance = `20 GB`; Calculator hiển thị `2.00 instance months` và 40 GB-month | Launch template root volume | Không nhập `40` vào ô storage per instance; không nhập EBS lần thứ hai |
| Application Load Balancer | 1 ALB × 730 giờ + LCU usage | 1 `aws_lb`, 2 public subnets | 2 AZ không có nghĩa là 2 ALB |
| RDS PostgreSQL | 1 `db.t3.micro` × 730 giờ, Single-AZ | `multi_az = false`, `publicly_accessible = false` | Không chọn Multi-AZ hoặc Publicly accessible |
| S3 Standard | 1 frontend bucket baseline; thêm artifact bucket nếu được cấu hình | Frontend bucket; artifact bucket là tùy chọn bên ngoài | Versioning hoặc artifact có thể làm storage thực tế lớn hơn 5 GB |
| CloudFront | 1 distribution, Price Class 100, viewer data/request | S3 origin + ALB origin | Không thêm viewer certificate/Route 53 cho baseline |
| CloudWatch | 7 standard alarms, 2 log groups, CloudWatch Calculator Metrics `7`, code-derived custom series `5` | Monitoring module và CloudWatch Agent | `alarm_actions` không tạo thêm alarm; Standard Logs input theo form là 2 GB |
| Public IPv4 | 4 in-use public IPv4 addresses; idle `0` | 2 EC2 + 2 ALB; RDS private | Không tính public IPv4 cho RDS |

Khi đối chiếu, lưu lại ba giá trị: **monthly total**, **one-time/other charges nếu có**, và **assumption/Free Tier mode**. Chỉ đánh dấu tổng cost là `Validated` khi estimate có URL share hoặc PDF/CSV được lưu cùng ngày kiểm tra.

## 7. Bảng baseline minh họa

Bảng này giúp kiểm tra phép tính, **không phải bằng chứng hóa đơn cuối cùng**. Các giá RDS/S3 cần lấy lại từ Calculator tại thời điểm estimate.

| Hạng mục | Công thức minh họa | Chi phí USD/tháng |
|---|---|---:|
| EC2 t3.micro | `2 × 730 × 0.0104` | 15.18 |
| EC2 root EBS gp3 | `20 GB/instance × 2.00 instance months × 0.08` | 3.20 |
| Public IPv4 | `4 × 730 × 0.005` | 14.60 |
| ALB | `730 × (0.0225 + 0.1 × 0.008)` | 17.01 |
| RDS compute | `730 × <Calculator db.t3.micro rate>` | Chờ Calculator |
| RDS gp3 | `20 × <Calculator RDS gp3 rate>` | Chờ Calculator |
| S3 Standard storage | `5 × <Calculator S3 Standard rate>` | Chờ Calculator |
| S3 requests | `1,000 PUT/LIST + 1,000,000 GET` | Chờ Calculator |
| S3 API artifact | `0` trong baseline vì `application_artifact_bucket = null` | Không tính; thêm nếu cấu hình bucket thật |
| CloudFront | `100 GB + 10M requests`, allowance hiện tại | Có thể 0 |
| CloudWatch alarms | `7 × 0.10`, trước allowance | 0.70 hoặc thấp hơn |
| CloudWatch logs/metrics | 2 GB Standard Logs, Calculator Metrics `7` / code-derived custom series `5` | Có thể 0 sau Free Tier |
| Secrets Manager | `0` trong baseline vì chỉ nhận ARN, không tạo secret | Thêm nếu secret tồn tại và do account sở hữu |
| **Subtotal phần đã có rate minh họa** | Không bao gồm RDS/S3 | **55.25** |

Nếu chỉ thay các placeholder bằng hai rate minh họa thường dùng là RDS `db.t3.micro = $0.017/giờ`, RDS gp3 `$0.115/GiB-month` và S3 Standard `$0.023/GiB-month`, subtotal trước allowance/discount xấp xỉ **$70.78/tháng**. Con số này chỉ dùng để sanity-check; không gọi là giá đã được AWS Calculator xác nhận.

## 8. Quy trình tạo estimate có evidence

1. Mở [AWS Pricing Calculator](https://calculator.aws/#/addService).
2. Chọn Region `US East (N. Virginia)` cho các regional resources.
3. Thêm EC2, mở phần **Amazon Elastic Block Store (EBS) - optional** bên trong EC2, rồi thêm ELB, RDS PostgreSQL, S3, CloudFront, CloudWatch và VPC. Trong VPC chỉ chọn **Public IPv4 Address**; không chọn VPN/NAT Gateway/Transit Gateway/PrivateLink hoặc feature không có trong kiến trúc. Chỉ thêm service EBS riêng nếu Calculator không nhận EBS trong EC2 estimate.
4. Nhập đúng usage table ở trên; không double-count EBS hoặc CloudFront origin transfer.
5. Tạo ít nhất hai scenario:
   - **Baseline gross:** chưa trừ Free Tier/credits/discount.
   - **Account-adjusted:** chọn Free Tier/offer phù hợp account nếu Calculator hỗ trợ.
6. Đặt tên estimate, lưu URL share hoặc tải PDF/CSV.
7. Ghi lại ngày tạo estimate, Region, usage assumptions và total vào change/PR artifact.
8. So sánh Calculator với công thức baseline; nếu lệch, kiểm tra trước các nguyên nhân: LCU, public IPv4, RDS backup, T3 CPU credits, CloudWatch free allowance và CloudFront viewer geography.

## 9. Evidence ledger

| Nội dung cần chứng minh | Evidence |
|---|---|
| Region và instance defaults | [`../../environments/dev/variables.tf#L18`](../../environments/dev/variables.tf#L18), [`../../environments/dev/variables.tf#L410`](../../environments/dev/variables.tf#L410) |
| ASG desired/min/max | [`../../environments/dev/variables.tf#L431`](../../environments/dev/variables.tf#L431), [`../../modules/compute/main.tf#L249`](../../modules/compute/main.tf#L249) |
| EC2 gp3 root volume | [`../../environments/dev/variables.tf#L417`](../../environments/dev/variables.tf#L417), [`../../modules/compute/main.tf#L208`](../../modules/compute/main.tf#L208) |
| API artifact bucket optional | [`../../environments/dev/variables.tf#L466`](../../environments/dev/variables.tf#L466), [`../../modules/compute/user_data.sh.tftpl#L22`](../../modules/compute/user_data.sh.tftpl#L22) |
| RDS Single-AZ/private/gp3 | [`../../modules/database/main.tf#L35`](../../modules/database/main.tf#L35), [`../../modules/database/main.tf#L50`](../../modules/database/main.tf#L50) |
| ALB count và 2 public subnets | [`../../modules/alb/main.tf#L3`](../../modules/alb/main.tf#L3), [`../../environments/dev/main.tf#L81`](../../environments/dev/main.tf#L81) |
| CloudFront S3 private origin + ALB origin | [`../../modules/frontend/main.tf#L97`](../../modules/frontend/main.tf#L97), [`../../modules/frontend/main.tf#L103`](../../modules/frontend/main.tf#L103) |
| Custom viewer domain optional | [`../../environments/dev/variables.tf#L183`](../../environments/dev/variables.tf#L183), [`../../modules/frontend/main.tf#L148`](../../modules/frontend/main.tf#L148) |
| 7 CloudWatch alarms | [`../../modules/monitoring/main.tf#L35`](../../modules/monitoring/main.tf#L35), [`../../modules/monitoring/outputs.tf#L16`](../../modules/monitoring/outputs.tf#L16) |
| CloudWatch custom metrics và agent interval | [`../../modules/compute/main.tf#L30`](../../modules/compute/main.tf#L30), [`../../modules/monitoring/main.tf#L162`](../../modules/monitoring/main.tf#L162) |
| No NAT Gateway | [`../../modules/network/main.tf#L96`](../../modules/network/main.tf#L96) |
| Official pricing references | [EC2](https://aws.amazon.com/ec2/instance-types/t3/), [EBS](https://aws.amazon.com/ebs/pricing/), [ALB](https://aws.amazon.com/elasticloadbalancing/pricing/), [RDS](https://aws.amazon.com/rds/postgresql/pricing/), [S3](https://aws.amazon.com/s3/pricing/), [CloudFront](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/), [CloudWatch](https://aws.amazon.com/cloudwatch/pricing/), [VPC](https://aws.amazon.com/vpc/pricing/), [Route 53](https://aws.amazon.com/route53/pricing/), [ACM](https://aws.amazon.com/certificate-manager/pricing/) |

## 10. Giới hạn và rủi ro

- **Usage uncertainty:** chưa có số liệu request, bandwidth, LCU, log ingestion, backup và database I/O.
- **Price drift:** giá AWS và Free Tier có thể thay đổi; estimate phải có ngày kiểm tra.
- **Free Tier/credits:** không áp dụng tự động cho mọi account và có thể thay đổi theo thời điểm/account plan.
- **T3 CPU credits:** có thể làm chi phí EC2 tăng nếu vượt baseline.
- **RDS backup/storage:** `max_allocated_storage = 100 GiB` là giới hạn autoscaling, không phải chi phí chắc chắn 100 GiB; chi phí tính theo storage thực tế provisioned.
- **Custom domain tương lai:** thêm Route 53 và viewer certificate chỉ khi bật; không được trừ regional ALB certificate khỏi cost model.
- **No deployment claim:** tài liệu này chỉ dựa trên HCL và assumptions, chưa chạy `terraform plan/apply` và chưa đọc AWS Cost Explorer.

## 11. Trạng thái tài liệu

- Planned: 0
- In progress: 0
- Implemented: 1
- Validated: 0
- Blocked: 1 — chưa có Calculator share/PDF và usage thực tế để xác nhận tổng cuối cùng
- Not in scope: 1 — không tạo AWS estimate account-side, không chạy `apply`, không dùng Cost Explorer của account
