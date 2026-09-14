# Documentation Checklist và Evidence Ledger

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** biến kế hoạch và kết quả triển khai thành tài liệu có thể kiểm tra, không chỉ là mô tả.

## Source of truth

Phân biệt vai trò của từng tài liệu:

| File | Vai trò |
|---|---|
| `docs/components/README.md` | kiến trúc mục tiêu và cây component |
| `docs/configuration/<module>/README.md` | kế hoạch cấu hình, acceptance criteria và checklist |
| `modules/<module>/README.md` | implementation contract và cách sử dụng module |
| HCL trong module/environment | trạng thái thực thi hiện tại |

Nếu các nguồn lệch nhau, ghi `Drift` hoặc `Blocked`; không đổi trạng thái thành `Validated` chỉ vì README đã viết.

## Checklist bắt buộc

Mỗi module được tạo hoặc hoàn thành phải có một bảng tương tự trong `docs/configuration/<module>/README.md`. Nếu repository chỉ định vị trí khác, dùng vị trí đó nhưng vẫn giữ các cột tối thiểu.

```markdown
## Implementation checklist

| # | Hạng mục | Trạng thái | Evidence code | Evidence validation | Consumer/ghi chú |
|---:|---|---|---|---|---|
| 1 | Boundary và non-goals | Planned | `docs/configuration/<module>/README.md:...` | Chưa xác minh | ... |
| 2 | Service/resource chính | Implemented | `modules/<module>/main.tf:...` | `terraform validate` — Chưa chạy | ... |
| 3 | Input contract | Validated | `modules/<module>/variables.tf:...` | `terraform validate` — Pass | ... |
| 4 | Output contract | Blocked | `modules/<module>/outputs.tf:...` | Lỗi ... | Consumer chưa có |
```

Không để literal `...` trong checklist cuối cùng. Chỉ dùng line thật được lấy sau khi file ổn định.

## Trạng thái và tiêu chí chuyển trạng thái

| Trạng thái | Điều kiện |
|---|---|
| `Planned` | Có thiết kế/acceptance criteria nhưng chưa có code được xác nhận |
| `In progress` | Đang code hoặc contract còn thiếu |
| `Implemented` | Resource/input/output đã tồn tại; validation chưa đủ hoặc chưa chạy |
| `Validated` | Hạng mục có code evidence và command phù hợp đã pass |
| `Blocked` | Có lỗi hoặc dependency cụ thể ngăn hoàn tất |
| `Not in scope` | Đã quyết định không làm trong task này |

`Implemented` không đồng nghĩa `Validated`. Không dùng `Done`, `Pass` hoặc checkbox đã tick để thay thế trạng thái chuẩn.

## Các nhóm checklist cần có

Tùy module, checklist phải bao phủ các nhóm sau và ghi `Not in scope` nếu không áp dụng:

1. Boundary, service/resource và số lượng.
2. Input, type, default, validation và sensitive.
3. Dependency, naming và tagging.
4. Security: ingress, egress, encryption, TLS, public/private, IAM.
5. Output và consumer/downstream.
6. Environment wiring và provider alias.
7. Test, `fmt`, `validate`, lint, security scan và plan.
8. Non-goals, known risk và blocker.

## Evidence rules

Mỗi dòng `Implemented` hoặc `Validated` phải có tối thiểu:

- code evidence: `path:line` cho definition/reference chính;
- validation evidence: command, kết quả và phạm vi chạy; hoặc lý do rõ nếu chưa chạy.

`Planned` có thể chỉ có design evidence. `Blocked` phải có lỗi/nguyên nhân và dependency cần gỡ. `Not in scope` phải có lý do ngắn.

Lấy line sau lần edit cuối:

```bash
rg -n 'variable "|resource "|data "|output "|module "' modules/<module> environments/<env>
nl -ba modules/<module>/variables.tf | sed -n '1,220p'
nl -ba modules/<module>/main.tf | sed -n '1,320p'
nl -ba modules/<module>/outputs.tf | sed -n '1,220p'
```

Nếu muốn dùng link Markdown, link phải trỏ đúng file/line; không tạo link hoặc line number phỏng đoán.

## Evidence chain

Mỗi public contract phải truy vết được theo chuỗi:

```text
design/checklist
  → module README
  → module variable
  → environment variable/module call
  → resource/data
  → module output
  → environment output/downstream consumer
```

Ví dụ output `vpc_id` chỉ được gọi là hoàn chỉnh khi có `output "vpc_id"`, module call có module đó, và consumer dùng đúng `module.<name>.vpc_id` hoặc environment re-export tương ứng.

## Trạng thái tổng quan

Đặt ngay sau tiêu đề hoặc trước checklist:

```markdown
## Trạng thái tổng quan

- Planned: 0
- In progress: 0
- Implemented: 0
- Validated: 0
- Blocked: 0
- Not in scope: 0
```

Các số phải đếm từ bảng checklist hiện tại; cập nhật cùng lúc khi thêm, xóa hoặc đổi trạng thái item.

## Kiểm tra docs

```bash
rg -n 'Implementation checklist|Trạng thái tổng quan|Planned|In progress|Implemented|Validated|Blocked|Not in scope' docs modules
git diff --check
```

Nếu có `markdownlint` hoặc `lychee`, chạy trong scope docs. Không báo `Pass` cho tool chưa cài hoặc command chưa chạy; ghi `Chưa xác minh`.

## Definition of done cho docs

- [ ] Kế hoạch được ghi trước khi code.
- [ ] Module README mô tả đúng implementation thực tế.
- [ ] Checklist có đủ service, variables, outputs, wiring, security và validation phù hợp.
- [ ] Mọi `Implemented`/`Validated` có evidence.
- [ ] Không còn line placeholder hoặc link sai.
- [ ] Trạng thái tổng quan khớp số dòng trong bảng.
- [ ] Drift/blocker/non-goals được ghi rõ.
