# ALB module

Tạo internet-facing ALB trên hai public subnet, target group HTTP cho NodeJS và health check `/health`. Listener mặc định trả `403`; rule chỉ forward `/api` và `/api/*` khi custom origin header khớp giá trị do CloudFront gửi. Vì vậy truy cập trực tiếp vào ALB không có header hợp lệ sẽ không tới EC2.

Mục tiêu thiết kế hiện tại là CloudFront kết nối tới ALB bằng HTTPS. ALB cần certificate regional hợp lệ và khớp hostname CloudFront sử dụng làm origin; ALB origin domain, DNS management và phương án validate certificate hiện chưa được chốt nên không được khẳng định HTTPS origin đã sẵn sàng. Certificate mặc định của CloudFront cho viewer `*.cloudfront.net` là độc lập và không thay thế certificate của ALB.

| Input chính | Output chính |
|---|---|
| subnet/SG, `target_port`, `certificate_arn` | `alb_dns_name`, `alb_arn` |
| `origin_custom_header_*`, `health_check_path` | target/listener ARN và suffix cho monitoring |
