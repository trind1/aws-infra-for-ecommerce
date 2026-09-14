# Security và Compliance

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** review security boundary, secret handling và evidence scan cho IaC.

## Threat model tối thiểu

Với mỗi service/resource, xác định:

- ai/what được phép truy cập;
- traffic đi vào/ra qua port, protocol và source/destination nào;
- resource public hay private;
- data có encryption at rest/in transit không;
- identity/IAM nào sở hữu hoặc đọc resource;
- log/audit nào cần giữ;
- blast radius nếu resource bị thay đổi hoặc xóa.

Nếu chưa đủ thông tin, đánh dấu `Blocked`/`Chưa xác minh`, không tự mở quyền để làm plan pass.

## Network và security group

- Chỉ mở port và source cần thiết; tránh `0.0.0.0/0` nếu không phải endpoint public có chủ ý.
- Tách ALB/app/database boundary; SG downstream nên reference SG upstream thay vì CIDR rộng khi có thể.
- Không trộn rule inline với `aws_vpc_security_group_ingress_rule`/`egress_rule` standalone.
- Ghi rõ ingress, egress, protocol, port và source trong README/checklist.
- Xác định public subnet/route/IGW/NAT theo thiết kế; không gọi subnet private nếu có route public.

## IAM, data và secret

- Least privilege: action/resource cụ thể, tránh `*` nếu không cần.
- Không commit secret trong source, `.tfvars`, default, tag hoặc output.
- `sensitive = true` chỉ che hiển thị; giá trị vẫn có thể nằm trong state.
- Ưu tiên Secrets Manager/Parameter Store/runtime lookup hoặc write-only argument khi runtime/provider hỗ trợ.
- S3/RDS/EBS/backup/log cần encryption at rest; TLS cho traffic và endpoint có yêu cầu.
- Không log plan/state có secret vào artifact công khai.

## Scan commands

```bash
trivy config .
checkov -d .
tflint --recursive
```

Chỉ ghi `Pass` khi command đã chạy và exit result phù hợp. Tool không cài là `Chưa xác minh`, không phải pass.

## Findings và mức độ

| Mức | Ví dụ | Hành động |
|---|---|---|
| Critical/High | secret lộ, public database, IAM admin ngoài scope | block review; phải sửa hoặc có exception rõ |
| Medium | thiếu encryption/logging, ingress rộng có thể thu hẹp | nêu remediation và owner |
| Low | naming/tag thiếu hoặc scan advisory | ghi backlog nếu không thuộc task |
| Informational | trade-off kiến trúc | ghi docs, không gọi là failure |

Mỗi finding phải có: path/line, tác động, exploit/blast radius, remediation, trade-off và trạng thái.

## Checklist evidence

- [ ] Public/private boundary khớp plan.
- [ ] Ingress/egress có source/destination và port cụ thể.
- [ ] Encryption/TLS được kiểm tra hoặc ghi `Not in scope`.
- [ ] IAM không rộng hơn boundary.
- [ ] Không có secret trong diff/README/output/log.
- [ ] Scan phù hợp đã chạy hoặc blocker được ghi.
- [ ] Finding được phản ánh vào checklist docs và response contract.
