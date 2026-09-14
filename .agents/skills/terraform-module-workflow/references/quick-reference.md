# Quick Reference

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** tra cứu nhanh command, luồng xử lý và cách phân loại task.

## Luồng chuẩn

```text
Khảo sát repository
        ↓
Chốt plan + docs/checklist
        ↓
variables.tf → main.tf → outputs.tf
        ↓
Wire vào environment
        ↓
fmt → validate → test/scan → plan
        ↓
Cập nhật evidence và kết luận
```

## Bảng định tuyến

| Cần làm | Đọc |
|---|---|
| Module boundary, variables, outputs | [module-patterns.md](module-patterns.md) |
| HCL structure, stable address, refactor | [code-patterns.md](code-patterns.md) |
| Docs plan, checklist, evidence | [docs-evidence.md](docs-evidence.md) |
| Test và validation | [testing-frameworks.md](testing-frameworks.md) |
| Security/compliance | [security-compliance.md](security-compliance.md) |
| State/backend/migration/destroy | [state-management.md](state-management.md) |
| CI/CD | [ci-cd-workflows.md](ci-cd-workflows.md) |
| LSP, definition, references, rename | [code-intelligence-lsp.md](code-intelligence-lsp.md) |

## Command nền tảng

```bash
terraform version
git status --short
terraform fmt -check -recursive
terraform -chdir=environments/<env> validate
terraform -chdir=environments/<env> plan -out=tfplan
git diff --check
```

Chỉ chạy `plan` sau khi init/provider/backend đã sẵn sàng. Nếu command bị chặn bởi credentials, network, provider ngoài scope hoặc module chưa hoàn chỉnh, ghi đúng lỗi thay vì suy đoán.

## Truy vết contract

```bash
rg -n 'variable "|resource "|data "|output "|module "' modules/<module> environments/<env>
nl -ba modules/<module>/variables.tf
nl -ba modules/<module>/main.tf
nl -ba modules/<module>/outputs.tf
```

Chuỗi phải kiểm tra được:

```text
docs plan → module README → variable → module call
          → resource/data → module output → environment/downstream consumer
```

## Trạng thái checklist

| Trạng thái | Ý nghĩa |
|---|---|
| `Planned` | Đã thiết kế, chưa có implementation được xác nhận |
| `In progress` | Đang triển khai, chưa đủ contract |
| `Implemented` | Code đã tồn tại, chưa đủ validation để gọi là validated |
| `Validated` | Code và validation command tương ứng đều pass |
| `Blocked` | Có blocker cụ thể; phải ghi lỗi và cách gỡ |
| `Not in scope` | Cố ý không làm trong task hiện tại |

Không dùng `Done` hoặc `Pass` thay cho các trạng thái trên trong checklist. `Validated` là trạng thái cao nhất của một hạng mục, không phải mặc định sau khi viết code.

## Khi kết thúc

Phản hồi phải nêu: kết quả, files, checklist summary, evidence matrix, assumptions/version floor, risk/trade-off, validation result và rollback/state mutation. Không claim apply nếu chỉ mới plan.
