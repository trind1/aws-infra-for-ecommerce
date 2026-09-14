---
name: terraform-module-workflow
description: Thiết kế, ghi chép, triển khai và review Terraform/OpenTofu theo module với nhiều reference chuyên biệt cho code, docs, testing, security, CI/CD, state và evidence.
---

# Terraform Module Workflow

Đây là một umbrella skill duy nhất cho công việc Terraform/OpenTofu trong repository. `SKILL.md` này là router và contract chung; hướng dẫn chuyên sâu nằm trong `references/` và chỉ được đọc khi phù hợp với task.

Phản hồi, kế hoạch và Markdown phải viết bằng tiếng Việt. Tên resource, thuộc tính provider, symbol HCL, command và error message có thể giữ tiếng Anh để khớp codebase.

## Khi dùng skill

Dùng khi:

- tạo hoặc sửa module Terraform/OpenTofu;
- nối module vào `environments/<env>`;
- lập kế hoạch cấu hình trước khi code;
- review contract giữa README, variables, resources, outputs và consumer;
- viết checklist docs, kiểm thử, CI/CD, security/compliance hoặc state workflow;
- điều tra rename, identity churn, provider/version hoặc lỗi validation.

Không dùng cho câu hỏi HCL cơ bản không liên quan đến repository hoặc câu hỏi cloud thuần túy không tạo/sửa IaC.

## Router: đọc reference theo chức năng

Đọc `quick-reference.md` trước mỗi task. Sau đó chỉ đọc reference tương ứng; không nạp toàn bộ tài liệu một cách máy móc.

| Tình huống | Reference cần đọc |
|---|---|
| Tạo/review module, input/output, boundary | [module-patterns.md](references/module-patterns.md) |
| Viết HCL, naming, block order, `count`/`for_each`, refactor | [code-patterns.md](references/code-patterns.md) |
| Viết README, checklist, trạng thái và evidence | [docs-evidence.md](references/docs-evidence.md) |
| `fmt`, `validate`, `plan`, native test, Terratest | [testing-frameworks.md](references/testing-frameworks.md) |
| SG, IAM, encryption, public exposure, scan | [security-compliance.md](references/security-compliance.md) |
| Backend, locking, migration, import, destroy, recovery | [state-management.md](references/state-management.md) |
| GitHub Actions, GitLab CI, Atlantis, reviewed plan | [ci-cd-workflows.md](references/ci-cd-workflows.md) |
| Tìm definition/reference, rename an toàn bằng LSP hoặc `rg` | [code-intelligence-lsp.md](references/code-intelligence-lsp.md) |

Nếu task chạm nhiều nhóm, đọc tất cả reference thuộc các nhóm đó và ghi rõ chúng trong phần evidence cuối cùng.

## Quy tắc ưu tiên

Áp dụng theo thứ tự:

1. Yêu cầu cụ thể mới nhất của người dùng.
2. Kiến trúc mục tiêu trong `docs/components/` và kế hoạch trong `docs/configuration/` nếu được chỉ định.
3. Contract và convention đã tồn tại trong repository.
4. Reference phù hợp trong skill này.
5. Suy luận mặc định của Terraform.

Nếu docs mục tiêu và code hiện tại khác nhau, không âm thầm sửa docs để hợp thức hóa code. Báo drift, chọn nguồn được người dùng chỉ định, hoặc dừng phần bị thiếu thông tin.

## Phạm vi và an toàn

- Chỉ sửa module, environment và docs nằm trong scope yêu cầu.
- Không tự thêm service, đổi topology, thêm validation nâng cao, đổi backend/provider alias hoặc đổi naming convention nếu chưa được yêu cầu.
- Không chạy `apply`, `destroy`, import hoặc thao tác remote state nếu người dùng chưa yêu cầu rõ.
- Trước khi sửa, chạy `git status --short`, đọc các file liên quan và diff hiện có.
- Không đổi resource address chỉ để làm code đẹp. Nếu rename ảnh hưởng state, dùng `moved`/import strategy và yêu cầu plan kiểm chứng.
- Không để secret trong source, committed `.tfvars`, default, tag, output không cần thiết hoặc log.

## Contract chung của repository

Áp dụng convention hiện có, lấy `modules/network` làm baseline khi không có yêu cầu mới:

- Module có `README.md`, `main.tf`, `variables.tf`, `outputs.tf`; chỉ thêm `versions.tf` khi module cần self-contained.
- `project_name` và `environment` giữ tên, description và type nhất quán với baseline.
- Variable required của module không tự thêm `default`, `nullable = false` hoặc validation chỉ vì muốn chặt hơn; validation chỉ xuất hiện khi có constraint thật.
- Provider composition layer chịu trách nhiệm `default_tags` nếu repository đã chọn cách đó; không tạo `tags` variable trong từng module chỉ để truyền common tags.
- `main.tf` nhóm resource theo service và dùng heading dạng:

~~~hcl
# ============ VPC  ============
resource "aws_vpc" "this" {
  # ...
}
~~~

- Output là public contract: luôn có `description`, chỉ xuất giá trị downstream/vận hành cần và phải có consumer hoặc lý do rõ ràng.
- Environment làm composition: truyền input, nối output, giữ defaults/provider/backend; module làm resource logic.

Chi tiết về module/code không đặt ở đây; đọc [module-patterns.md](references/module-patterns.md) và [code-patterns.md](references/code-patterns.md).

## Quy trình bắt buộc

### 1. Khảo sát

Xác định runtime/version, provider/alias/region/account, backend/locking, environment/criticality, module upstream/downstream và thay đổi đang có.

~~~bash
terraform version
rg --files -g '*.tf' -g '*.tfvars*' -g 'README.md' -g '*.hcl'
rg -n 'module "|resource "|data "|output "|variable "|provider "|backend ' .
git status --short
~~~

Đọc theo thứ tự: environment `main.tf` → `variables.tf` → `outputs.tf` → provider/version/backend → `docs/components/` và `docs/configuration/` → module mục tiêu → consumer.

### 2. Lập kế hoạch và docs trước code

Trước resource đầu tiên, tạo/cập nhật:

- `docs/configuration/<module>/README.md`: kế hoạch cấu hình, service/resource, boundary, inputs/outputs, security, dependencies, non-goals và checklist.
- `modules/<module>/README.md`: contract sử dụng và mô tả implementation; không mô tả resource chưa tồn tại.

Khi repository đã quy định một vị trí docs khác, giữ cấu trúc đó nhưng phải có đúng một checklist có thể truy vết. Đọc [docs-evidence.md](references/docs-evidence.md).

### 3. Implement module contract

Làm theo thứ tự: `variables.tf` → `main.tf` → `outputs.tf`. Mỗi resource, variable và output phải có mục tương ứng trong docs. Dùng direct reference để Terraform tự suy luận dependency; chỉ dùng `depends_on` khi expression không thể hiện đủ quan hệ.

### 4. Wire environment

Chỉ sau khi module contract hoàn chỉnh mới thêm module block, environment variables và environment outputs. Kiểm tra hai chiều:

- mọi module input có nguồn từ environment hoặc output upstream;
- mọi output được consumer dùng đều tồn tại và giữ đúng tên;
- provider alias được truyền khi module yêu cầu;
- common tags chỉ áp dụng ở layer đã thống nhất.

### 5. Validate và ghi evidence

Chạy command phù hợp với scope. `fmt`/`validate` không thay thế `plan`, test, security scan hoặc review docs. Mọi kết luận phải kèm file path + line, command + exit result, và trạng thái `Pass`, `Fail`, `Chưa xác minh`, `Blocked` hoặc `Pre-existing failure`.

Đọc [testing-frameworks.md](references/testing-frameworks.md) cho test; [security-compliance.md](references/security-compliance.md) cho scan; [docs-evidence.md](references/docs-evidence.md) cho checklist và evidence ledger.

## Response contract

Mọi task kết thúc bằng tiếng Việt và có các phần sau:

1. **Kết quả:** đã làm gì, file nào đổi, phần nào cố ý không đụng tới.
2. **Contract/evidence matrix:** Variables, Resources, Outputs, Wiring, Documentation checklist và Validation; mỗi dòng có `path:line` hoặc command/result.
3. **Trạng thái docs:** số lượng `Planned`, `Implemented`, `Validated`, `Blocked`, `Not in scope`; không tự bịa số.
4. **Assumptions:** runtime/version, provider, backend, execution path và criticality; điều chưa biết phải ghi là giả định.
5. **Risk và trade-off:** chọn trong identity churn, secret exposure, blast radius, CI drift, compliance gaps, state corruption, provider upgrade risk, testing blind spots; nêu rủi ro còn lại.
6. **Validation:** command đã chạy, exit result, lỗi ngoài scope và phần chưa chạy.
7. **Rollback:** nếu chưa mutate state, ghi rõ `Chưa có state mutation`; nếu có rename/migration/state mutation thì nêu plan artifact, backup và procedure.

Không gọi `plan` là `apply`. Không gọi là “đã hoàn tất” khi checklist còn item `Implemented` chưa được kiểm chứng hoặc còn `Blocked` mà chưa nêu lý do.

## Version floor

Kiểm tra version thực tế trước khi dùng feature mới. Baseline repository hiện tại là Terraform `>= 1.5.0` và AWS provider `~> 6.0`; feature yêu cầu cao hơn phải được guard bằng version constraint và yêu cầu rõ ràng.
