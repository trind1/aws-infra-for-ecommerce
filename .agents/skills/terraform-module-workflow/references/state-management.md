# State Management

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** giảm state corruption, identity churn và destroy ngoài chủ ý.

## Backend và locking

Team/staging/production không nên dùng local state. Backend phải có encryption, versioning/backup, access control, audit và locking phù hợp.

AWS S3 mới có thể dùng native lock file nếu runtime hỗ trợ:

```hcl
terraform {
  backend "s3" {
    bucket       = "example-terraform-state"
    key          = "dev/network/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

Không tự đổi backend hoặc locking trong task module. Backend migration là task riêng, cần backup và plan/approval.

## State layout

Tách state theo environment/component khi lifecycle, owner hoặc blast radius khác nhau. Không chia nhỏ resource có dependency chặt chỉ để giảm file.

| Pattern | Dùng khi |
|---|---|
| Per environment | stack nhỏ, cùng lifecycle |
| Per component | module độc lập, team/approval khác |
| Hybrid | environment và component đều cần isolation |

## Identity stability

- Dùng `for_each` map với key nghiệp vụ ổn định cho nhiều resource.
- Tránh list index dài hạn khi reorder/remove.
- Không đổi resource label/address chỉ vì convention đẹp hơn.
- Refactor address phải có `moved` block hoặc migration plan và plan không có destroy ngoài chủ ý.

Ví dụ:

```hcl
moved {
  from = aws_security_group.old
  to   = aws_security_group.alb
}
```

Không thêm `moved` nếu chưa xác định address cũ/mới; evidence phải lấy từ state/config thực tế.

## Import và provider lifecycle

- Import resource hiện hữu cần xác định exact address, ID, provider alias và config tương ứng.
- Không remove provider alias khi resource dùng alias còn trong state.
- `removed` block hoặc state command phải có review vì có thể làm mất ownership của Terraform.
- Không commit state, plan chứa secret hoặc credentials.

## Safe destroy protocol

Không chạy destroy, kể cả targeted destroy, nếu chưa:

1. chạy `terraform plan -destroy` đúng root/workspace;
2. đọc toàn bộ resource sẽ xóa, gồm implicit dependent từ locals/`for_each`;
3. lưu plan/output cần thiết;
4. xác nhận rõ với người dùng trước khi thực thi;
5. không dùng `-auto-approve` cho destroy.

## Recovery checklist

- [ ] Xác định workspace/backend/key chính xác.
- [ ] Kiểm tra lock đang do run nào giữ trước khi force unlock.
- [ ] Lấy backup/version state trước migration/recovery.
- [ ] Phân biệt drift thật với state/config mismatch.
- [ ] Dùng `state mv`/`import`/`moved` có review, không text replace mù.
- [ ] Plan sau recovery và ghi evidence vào checklist docs.
