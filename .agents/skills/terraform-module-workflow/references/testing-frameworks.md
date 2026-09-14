# Testing Frameworks

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** chọn validation/test theo rủi ro và phân biệt syntax, plan, runtime và integration.

## Tầng kiểm chứng

| Tầng | Kiểm tra | Khi dùng |
|---|---|---|
| Format | `terraform fmt -check -recursive` | Mọi thay đổi HCL |
| Static validation | `terraform validate` | Mọi module/environment sau init |
| Lint | `tflint` | Provider-specific best practices |
| Security scan | `trivy config`, `checkov` | HCL có IAM, network, data hoặc public exposure |
| Plan | `terraform plan -out=tfplan` | Trước review/apply |
| Native test | `terraform test` | Terraform 1.6+, logic module có test |
| Integration | Terratest hoặc apply test fixture | Computed value và cloud integration |

Không kết luận module đúng chỉ từ `fmt`. `validate` chứng minh syntax/internal consistency, không chứng minh security, resource behavior hoặc plan mong muốn.

## Luồng validation mặc định

```bash
terraform version
terraform fmt -check -recursive
terraform -chdir=environments/<env> validate
terraform -chdir=environments/<env> plan -out=tfplan
git diff --check
```

Nếu có tool:

```bash
tflint --recursive
trivy config .
checkov -d .
```

Không bắt buộc chạy `plan` ở module con nếu module không phải root configuration. Ưu tiên validate/plan ở composition có provider, variables và backend thật.

## Native test

Với Terraform 1.6+:

```bash
terraform test
terraform test -verbose
```

Quy tắc:

- `command = plan` phù hợp cho giá trị suy ra từ input.
- Computed values như ARN/name tạo bởi provider cần `command = apply` hoặc integration test.
- Không index nested block có type `set` bằng `[0]`; dùng expression phù hợp hoặc apply test.
- Mock provider (Terraform 1.7+) chỉ dùng khi schema và assertion không cần API thật.
- Test không được ghi secret hoặc bỏ resource test mà không cleanup.

## Khi dùng Terratest

Chọn Terratest khi cần AWS API thật, computed attributes, cross-module integration hoặc lifecycle behavior. Tất cả test resource phải:

- có naming/tag test rõ;
- có cleanup an toàn;
- dùng account/region dành cho test;
- không chạy ngầm trong production state;
- ghi chi phí và thời gian trong plan.

## Đọc kết quả

| Kết quả | Cách ghi evidence |
|---|---|
| Pass | command, working directory, exit 0 và phạm vi |
| Fail do task | lỗi thuộc file/scope vừa sửa |
| Pre-existing failure | lỗi đã có, nằm ngoài scope; kèm path/lỗi |
| Blocked | chưa chạy do credential/provider/network/dependency |
| Chưa xác minh | chưa thực hiện command; không gọi là pass |

Nếu module standalone fail vì chưa init provider nhưng root composition chưa fail, ghi đúng failure mode và không sửa module bằng workaround không được yêu cầu.

## Test checklist

- [ ] Đã xác định runtime và feature floor.
- [ ] Đã format check.
- [ ] Đã validate đúng root module/composition.
- [ ] Đã kiểm tra plan nếu task thay đổi resource graph.
- [ ] Đã chạy lint/scan khi rủi ro yêu cầu.
- [ ] Native/integration test không index sai set và có cleanup.
- [ ] Kết quả được ghi vào checklist docs bằng command + exit result.
