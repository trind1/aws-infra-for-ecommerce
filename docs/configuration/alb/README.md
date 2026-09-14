# Kế hoạch cấu hình: alb

## Mục tiêu

Đặt một Application Load Balancer public làm origin API cho CloudFront, cân bằng traffic tới EC2 Auto Scaling Group và chỉ chấp nhận request hợp lệ từ distribution. Mục tiêu hiện tại là CloudFront kết nối tới ALB bằng HTTPS; custom viewer domain không điều khiển certificate hoặc protocol của origin.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| Elastic Load Balancing v2 | Một internet-facing ALB trải trên hai public subnets. |
| Target group | Target type phù hợp EC2/instance; gửi traffic HTTP tới application port; health check path được cấu hình. |
| Listener | HTTPS listener cho CloudFront origin theo mục tiêu hiện tại; dùng certificate regional của ALB khớp ALB origin domain. |
| Listener rule | Yêu cầu custom origin header do CloudFront gửi; request không có header hợp lệ không được forward tới API. |
| Access and operational settings | Chốt deletion protection, idle timeout, SSL policy và health-check thresholds ở environment. |

## Input cần quyết định

- VPC ID, chính xác hai public subnet IDs và ALB security group ID.
- API port, health-check path và listener port/protocol.
- ALB origin domain/hostname, ACM ARN regional và SSL policy khi listener dùng HTTPS. Domain/DNS management và cách validate certificate hiện chưa được chốt.
- Tên header và giá trị bí mật chia sẻ giữa ALB với CloudFront.
- Deletion protection, idle timeout và tags.

## Output contract

- ALB ARN, DNS name và hostname contract mà CloudFront dùng làm origin.
- Target group ARN cho compute đăng ký ASG.
- Listener ARN/port cho kiểm soát và observability.
- ALB và target-group metric suffixes cho monitoring.

## Điều kiện chấp nhận

- ALB chỉ nằm trong public subnets và dùng ALB security group.
- Certificate regional phải hợp lệ và khớp ALB origin domain; không giả định certificate cho DNS mặc định `*.elb.amazonaws.com`.
- CloudFront → ALB giữ protocol HTTPS; nếu origin domain, DNS hoặc certificate chưa có phương án kiểm chứng thì trạng thái là `BLOCKED`.
- Không forward request API nếu custom header không khớp.
- Health check phản ánh endpoint sẵn sàng của application, không chỉ kiểm tra kết nối TCP.
