# Imported certificates module

Module import certificate PEM được generate ngoài Terraform vào ACM để gắn cho ALB
HTTPS test. Module không tạo DNS, Route 53, CloudFront, public CA hoặc hosted zone.

## Local workflow

```bash
ALB_CERT_DOMAIN=e-commerce-ndt.test \
  bash scripts/generate-alb-self-signed-cert.sh environments/dev/local-certs
```

Certificate phải có SAN `DNS:e-commerce-ndt.test`. Truyền `certificate_file` và
`private_key_file` từ ignored local `.tfvars`; không commit private key.

## Security boundary

- Chỉ dùng dev/test hoặc internal access.
- Client phải trust certificate để browser không cảnh báo TLS.
- `private_key_wo` giảm khả năng lưu private key trong Terraform state, nhưng file local
  vẫn là secret cần bảo vệ.
- Imported certificate không tự động renew; rotate bằng certificate mới và tăng
  `certificate_version`.

## Inputs/outputs

Inputs: `project_name`, `environment`, `certificate_file`, `private_key_file` và
`certificate_version`. Output: `certificate_arn` cho ALB HTTPS listener.

## Trạng thái

| Hạng mục | Trạng thái |
|---|---|
| Local self-signed generation script | Implemented |
| ACM imported certificate resource | Implemented, chưa apply |
| ALB HTTPS wiring | Implemented, chưa apply |
| Local DNS/trust store | Ngoài Terraform |
| Public certificate cho CloudFront | Not in scope |
