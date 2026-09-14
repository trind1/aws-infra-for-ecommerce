# CI/CD Workflows

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** tạo pipeline reproducible, reviewable và tránh local/CI drift.

## Pipeline chuẩn

```text
format → init → validate → test/scan → plan artifact → approval → apply artifact
```

`apply` phải dùng đúng plan artifact đã review, không chạy lại `plan` trong apply job. Production cần environment protection/approval và credential ngắn hạn.

## GitHub Actions tối thiểu

```yaml
name: Terraform

on:
  pull_request:
  push:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
      - run: terraform fmt -check -recursive
      - run: terraform init -input=false
      - run: terraform validate
      - run: terraform plan -input=false -out=tfplan
```

Đây là khung; phải đổi working directory, version, backend auth và policy theo repository. Không copy nguyên mẫu nếu root configuration không ở repository root.

## CI invariants

- Pin Terraform/OpenTofu version và provider; commit lock file theo policy.
- Dùng cùng working directory, variables, backend semantics và provider alias ở local/CI.
- Không ghi secret vào log/plan artifact; dùng OIDC hoặc secret manager.
- Pull request có plan review; apply chỉ từ branch/environment được bảo vệ.
- Security/policy scan chạy trên mọi đường dẫn tới apply.
- Plan artifact có retention, access control và gắn commit SHA.
- Test resource có tag và cleanup; tránh apply cloud thật trên mọi PR nếu không cần.

## Cost control

- PR: format, validate, static test, mock provider và policy scan.
- Main/scheduled: integration test hoặc plan với cloud thật.
- Dùng fixture nhỏ, TTL/tag cleanup và account test riêng.
- Không dùng `-auto-approve` cho production apply nếu quy trình yêu cầu approval.

## Atlantis/GitLab

Dù dùng GitHub Actions, GitLab CI hay Atlantis, giữ các invariant: same runtime/provider lock, plan artifact review, approval boundary, policy scan và evidence retention. Tool khác nhau không làm thay đổi state safety.

## CI review checklist

- [ ] Format, init và validate chạy đúng root.
- [ ] `terraform.lock.hcl`/runtime policy được xử lý nhất quán.
- [ ] Plan được lưu và apply dùng lại artifact đã review.
- [ ] Không lộ credentials/secret trong output.
- [ ] Policy/security stage không bị bypass.
- [ ] Environment production có approval/protection.
- [ ] CI result được ghi vào checklist docs bằng command/job và trạng thái.
