# ALB configuration

## Mục tiêu

ALB là entry point trực tiếp cho API test:

```text
Client CIDR → HTTPS e-commerce-ndt.test:443 → ALB → HTTP EC2/Docker:3000
```

HTTPS kết thúc tại ALB. Target group vẫn dùng HTTP vì traffic ALB → EC2 nằm trong VPC.

## Contract

| Hạng mục | Giá trị mục tiêu |
|---|---|
| ALB | Internet-facing, hai public subnets |
| HTTPS listener | `443`, certificate ARN từ `certificates-imported` |
| Routing | `/api` và `/api/*` tới target group |
| Target group | Instance target, HTTP `3000` |
| Health check | HTTP `/health`, expected `200` |
| Client access | Chỉ `alb_https_client_cidr_blocks` |
| Custom header | Không bắt secret header cho browser direct API |

## Hành vi listener

HTTPS direct API rule chỉ match path `/api` và `/api/*`, không yêu cầu
`X-Origin-Verify`. Rule HTTP legacy của CloudFront vẫn giữ điều kiện header riêng.

## Dependencies

- `network.public_subnet_ids`
- `security-groups.alb_security_group_id`
- `certificates-imported.certificate_arn`
- `compute.target_group_arn`

## Checklist

| Hạng mục | Trạng thái |
|---|---|
| ALB public và target group HTTP `3000` | Current |
| HTTPS listener `443` | Implemented, chưa apply |
| Imported certificate wiring | Implemented, chưa apply |
| Client CIDR ingress | Implemented, chưa apply |
| Direct API rule không yêu cầu `X-Origin-Verify` | Implemented, chưa apply |
| ALB access verification | Chưa xác minh trên AWS |

## Validation sau code

```bash
terraform fmt -check -recursive
terraform -chdir=environments/dev validate
terraform -chdir=environments/dev plan -out=dev.tfplan
```
