# Code Patterns và Structure

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** giữ HCL dễ đọc, address ổn định và refactor an toàn.

## Thứ tự file và block

Chuẩn module: `README.md` → `variables.tf` → `main.tf` → `outputs.tf`; `versions.tf` nếu module cần constraint riêng.

Trong resource, dùng thứ tự:

1. `count` hoặc `for_each`;
2. arguments chính theo nhóm logic;
3. `tags`;
4. `depends_on` nếu thật sự cần;
5. `lifecycle` ở cuối.

Trong variable: `description` → `type` → `default` → `nullable` → `validation` → `sensitive` theo convention của repository. Nếu baseline hiện tại đặt thứ tự khác, giữ baseline của repository để tránh diff không cần thiết.

## Heading và comment

Nhóm resource theo service, mỗi nhóm có heading nhất quán:

```hcl
# ============ VPC  ============

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
}
```

Comment giải thích boundary hoặc quyết định không hiển nhiên; không dùng comment thay cho README hay lặp lại từng attribute.

## `count` và `for_each`

| Trường hợp | Chọn | Lý do |
|---|---|---|
| Bật/tắt một singleton | `count = condition ? 1 : 0` | Mô hình boolean rõ |
| Nhiều named resource | `for_each = map` | Address theo key ổn định |
| List có thể reorder/remove | `for_each` với key ổn định | Tránh index churn |
| Consumer cần reference theo tên | `for_each = map` | Truy cập trực tiếp theo key |

Không dùng list index làm identity dài hạn. Khi refactor resource address đang có state, thêm `moved` block hoặc migration plan; không tự rename rồi coi là cleanup.

## Dependency

- Ưu tiên expression reference (`subnet_id = aws_subnet.private[each.key].id`) để Terraform tự lập graph.
- Chỉ dùng `depends_on` khi dependency không thể biểu diễn qua attribute.
- Không dùng `depends_on` rộng ở module nếu dependency có thể làm graph quá lớn.
- `locals` dùng để chuẩn hóa dữ liệu và giữ graph rõ; không dùng để che contract mơ hồ.

## Resource implementation

- Không hard-code region, account, secret hoặc identifier của environment.
- Dùng resource-native behavior thay cho provisioner; `local-exec`/`remote-exec` chỉ là last resort và phải nêu risk.
- Không trộn inline `ingress`/`egress` với `aws_vpc_security_group_*_rule` standalone trong cùng security group.
- Lifecycle (`create_before_destroy`, `prevent_destroy`, `ignore_changes`) phải có lý do và evidence; không dùng để che drift.
- Chỉ thêm `ignore_changes` khi biết chính xác hệ thống nào là owner của attribute.

## Version và feature guard

| Feature | Version tối thiểu | Guard |
|---|---:|---|
| `nullable = false` | Terraform 1.1 | Chỉ dùng khi repo floor hỗ trợ |
| `moved` block | Terraform 1.1 | Luôn plan để kiểm tra address |
| typed `optional()` default | Terraform 1.3 | Kiểm tra `required_version` |
| `import` block | Terraform 1.5 | Không thay thế import review |
| `check` block | Terraform 1.5 | Phân biệt check với variable validation |
| `terraform test` | Terraform 1.6 | Chạy đúng runtime |
| mock provider | Terraform 1.7 | Chỉ dùng khi test schema phù hợp |
| `use_lockfile` S3 | Terraform 1.10 | Không dùng nếu floor thấp hơn |
| write-only argument | Terraform 1.11 | Kiểm tra provider hỗ trợ |

Baseline repository là Terraform `>= 1.5.0`; không phát sinh feature yêu cầu cao hơn mà chưa cập nhật constraint.

## Refactor an toàn

Trước rename:

```bash
rg -n 'aws_[a-z0-9_]+\.[a-z0-9_]+' modules environments
rg -n 'module\.[a-z0-9_]+\.[a-z0-9_]+' modules environments
```

Tìm definition và reference, đọc lại từng file sau mỗi nhóm edit, chạy `fmt` và `validate`, rồi xem plan. Nếu có resource address đổi, plan phải cho thấy lý do và không được có destroy ngoài chủ ý.

## Lỗi thường gặp của agent

- Đổi tên `app_port`/`application_port` không cập nhật cả hai layer.
- Tạo output nhưng quên re-export ở environment hoặc consumer.
- Dùng `tags` variable trong module dù provider đã có `default_tags`.
- Thêm validation “nâng cao” không có yêu cầu nghiệp vụ.
- Dùng `depends_on` để che reference sai.
- Gọi `terraform validate` pass trong module con nhưng composition vẫn hỏng.
- Ghi docs theo code chưa hoàn chỉnh thay vì đánh dấu drift/blocker.
