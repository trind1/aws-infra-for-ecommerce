# Code Intelligence và Rename An toàn

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** tìm definition/reference có ngữ nghĩa và giảm lỗi khi đổi tên HCL.

## Ưu tiên công cụ

`terraform-ls` là tùy chọn. Nếu có LSP position-based, dùng cho symbol relationship; nếu không, dùng `rg` + đọc từng file và phải nói rõ fallback trong evidence.

| Mục tiêu | Cách làm |
|---|---|
| Definition/reference của symbol | `goToDefinition`, `findReferences` hoặc `rg` + Read |
| Resource/module address | semantic search + `moved` + plan |
| Rename variable/local/output/alias | tìm tất cả ref, sửa từng file, validate |
| Tìm exact text/non-HCL | `rg` |

Không gọi công cụ LSP unsupported rồi kết luận “LSP hỏng”. Chỉ dùng capability có thật của transport.

## Position anchoring

Nếu LSP hỗ trợ, xác định `filePath`, line và character bằng search trước; không gọi theo symbol name mơ hồ. Workspace cần được `terraform init` để resolve cross-module/provider. `init` có thể tải dependency nên chỉ chạy trong thư mục tin cậy.

## Fallback `rg`

```bash
rg -n 'variable "project_name"|var\.project_name' modules environments
rg -n 'output "vpc_id"|module\.[a-z0-9_-]+\.vpc_id' modules environments
rg -n 'module "|resource "|data "|provider "' modules environments
```

Sau search phải đọc file theo context; `rg` không hiểu scope như HCL parser và có thể bắt comment/string.

## Rename protocol

1. Xác định definition, mọi reference và resource address có state hay không.
2. Đọc từng file trước khi edit; không blind replace toàn repository.
3. Nếu đổi value symbol, sửa definition và tất cả reference cùng contract.
4. Nếu đổi resource address, chuẩn bị `moved` block; không chỉ đổi label.
5. Re-read diff, chạy `fmt`, `validate` và `plan`.
6. Xác nhận không có destroy ngoài chủ ý.
7. Cập nhật README/checklist và evidence line sau edit.

## Anti-pattern

- Chỉ sửa definition rồi quên environment consumer.
- Dùng `sed`/replace mù cho token trùng trong comment/string.
- Tạo shim command giả để mô phỏng LSP.
- Claim toàn bộ reference đã được tìm thấy khi chỉ search một thư mục.
- Đổi `module.<name>`/output name mà không kiểm tra downstream.
