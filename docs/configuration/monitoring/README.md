# Kế hoạch cấu hình: monitoring

## Mục tiêu

Tập trung log và alarm cho application, ALB, Auto Scaling Group và RDS; tách log foundation khỏi alarm wiring để không tạo vòng phụ thuộc.

## Dịch vụ và cấu hình

| Dịch vụ | Cấu hình mục tiêu |
|---|---|
| CloudWatch Log Groups | Hai log groups riêng cho API và system log; tạo trước compute, retention cấu hình được. |
| CloudWatch Logs metric filter | Trích xuất số lỗi application từ API log theo pattern được thống nhất. |
| CloudWatch Alarms cho ALB | Báo 5XX và unhealthy targets dựa trên ALB/target-group metric suffixes. |
| CloudWatch Alarms cho ASG | Báo CPU và số instance in-service; ASG name lấy từ compute output. |
| CloudWatch Alarms cho RDS | Báo CPU và free storage; DB identifier lấy từ database output. |
| Notification actions | Danh sách ARN đích nhận cảnh báo được truyền từ environment; không hard-code topic/account. |

## Hai pha cấu hình

1. **Log foundation:** tạo API/system log groups, xuất tên log groups cho compute.
2. **Alarms và metric filters:** sau khi ALB, compute và database xuất identifiers, tạo filters/alarms bằng các giá trị đó.

## Input cần quyết định

- API/system log retention và custom metric namespace.
- Error pattern của application log.
- ALB/target group metric suffixes, ASG name, DB identifier.
- Threshold, evaluation periods, missing-data policy và alarm actions.

## Output contract

- API log group name và system log group name cho compute.
- Metric namespace và alarm identifiers cho vận hành.

## Điều kiện chấp nhận

- Compute không phụ thuộc vào resources alarm để có tên log group.
- Mỗi alarm có metric dimension đúng resource và notification action tường minh.
- Retention đáp ứng yêu cầu môi trường, tránh để log vô hạn không chủ đích.
