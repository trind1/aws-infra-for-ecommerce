# Kế hoạch cấu hình: compute

## Mục tiêu

Chạy API trên EC2 Auto Scaling Group trong public subnets, nhận traffic từ ALB, kết nối private tới RDS và gửi log/metrics về CloudWatch.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| IAM | Instance role và instance profile với quyền tối thiểu cho SSM, CloudWatch Logs, artifact bucket và database secret. |
| EC2 launch template | AMI, instance type, application security group, encrypted gp3 EBS, IMDSv2 và user data để bootstrap ứng dụng. |
| EC2 Auto Scaling | ASG trải trên public subnet IDs, gắn API target group; cấu hình min/desired/max capacity và health-check grace period. |
| Auto Scaling policy | Target tracking theo CPU với target value do environment quyết định. |
| Application bootstrap | Lấy artifact và secret qua IAM; cấu hình DB endpoint/port/name và ghi API/system logs vào log groups được cấp. |

## Input cần quyết định

- AMI ID, instance type, key pair (nếu cần), root volume size và detailed monitoring.
- Public subnet IDs, application security group ID và API target group ARN.
- Min/desired/max capacity, CPU target value, health-check grace period và app port.
- Artifact bucket/key, start command và IAM policy scope tối thiểu.
- Database endpoint/port/name/user cùng secret ARN; không truyền password dạng plain text.
- API/system log group names và metric namespace từ monitoring log foundation.

## Output contract

- Auto Scaling Group name/ARN cho monitoring.
- Launch template ID cho kiểm toán/thay đổi phiên bản.
- Instance role ARN và instance profile name cho policy audit.

## Điều kiện chấp nhận

- EC2 chỉ nhận application traffic từ ALB security group.
- IMDSv2 và encrypted EBS là mặc định bắt buộc.
- Role không có quyền wildcard vượt nhu cầu artifact, logs, SSM và secret được xác định.
- Application chỉ được đưa vào target group khi health check của ALB thành công.
