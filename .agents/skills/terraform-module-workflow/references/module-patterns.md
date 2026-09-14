# Module Patterns

> **Thuộc skill:** [terraform-module-workflow](../SKILL.md)
> **Mục đích:** thiết kế module reusable, boundary rõ ràng và contract inputs/outputs ổn định.

## Phân loại module

| Loại | Phạm vi | Ví dụ |
|---|---|---|
| Resource module | Một nhóm resource liên kết chặt | VPC + subnet, SG + rules |
| Infrastructure module | Nhiều nhóm resource cho một mục đích | Networking stack |
| Composition | Điều phối environment/account/region | `environments/dev` |

Ưu tiên resource module nhỏ, ít dependency ngoài và có public contract rõ. Environment không chứa resource logic nếu logic đó thuộc module.

## Cấu trúc tối thiểu

```text
modules/<module>/
├── README.md
├── main.tf
├── variables.tf
└── outputs.tf

environments/<env>/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── versions.tf
└── backend.tf
```

Chỉ thêm `versions.tf`, `examples/` hoặc `tests/` khi có nhu cầu thật và phải ghi trong plan.

## Boundary checklist

Trước khi code, trả lời:

- Module tạo những service/resource nào? Số lượng và relationship ra sao?
- Module nhận dependency nào từ bên ngoài?
- Module chịu trách nhiệm naming, tagging, security và lifecycle nào?
- Module không tạo gì?
- Output nào có consumer thực tế?
- Resource nào có thể gây replacement hoặc cần migration?

Không thêm service vì “tiện” nếu service đó có lifecycle, quyền hoặc state boundary khác.

## Variable contract

Mỗi variable public cần `description` và `type` rõ ràng.

```hcl
variable "project_name" {
  description = "Project identifier used in resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}
```

Quy tắc:

- Required input không có `default`.
- Chỉ dùng `nullable = false` khi null thực sự không hợp lệ hoặc là convention đã chốt.
- Chỉ thêm validation cho constraint provider/nghiệp vụ, không thêm validation nâng cao chưa được thiết kế.
- Dùng type cụ thể (`string`, `number`, `bool`, `list(string)`, `set(string)`, `map(string)`, typed object).
- Secret phải `sensitive = true` ở nơi phù hợp nhưng vẫn phải nhớ rằng state có thể chứa giá trị đó.
- Tên input giữa environment và module phải nhất quán; nếu mapping bắt buộc, ghi trong README và evidence.

## Output contract

```hcl
output "vpc_id" {
  description = "ID of the application VPC."
  value       = aws_vpc.this.id
}
```

Output chỉ nên là ID, ARN, name, endpoint hoặc collection thật sự cần. Không export toàn bộ provider object. Output list phải có thứ tự ổn định nếu consumer dùng theo AZ/index. Output nhạy cảm phải đánh dấu `sensitive = true`.

## Environment composition

```hcl
module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.network.vpc_id
}
```

Kiểm tra hai chiều: mọi input module có source; mọi `module.<name>.<output>` có output definition; provider alias được truyền qua `providers` khi cần.

## Naming và tagging

- Resource singleton có thể dùng `this`; resource nhiều vai trò dùng tên mô tả (`alb`, `database`, `public`).
- Name tag phải ổn định và phản ánh project/environment/component.
- Nếu provider đã cấu hình `default_tags`, module không tạo `tags` variable chỉ để lặp common tags.
- Module vẫn có thể thêm tags riêng như `Name`, `Component`, `Tier` khi không ghi đè common tags.

## Module release/review checklist

- [ ] Boundary và non-goals đã ghi trong README.
- [ ] Variables có type/description và constraint cần thiết.
- [ ] Resources tạo đúng service đã thiết kế.
- [ ] Outputs có consumer và description.
- [ ] Không có secret hard-code.
- [ ] Không có resource address churn ngoài chủ ý.
- [ ] README, environment wiring và checklist docs khớp HCL.
- [ ] Validation evidence có command và `path:line`.
