# Imported certificates module

Module import certificate và private key PEM được chuẩn bị ngoài Terraform vào AWS
Certificate Manager (ACM). Trong environment `dev`, certificate này được gắn cho ALB
HTTPS listener để phục vụ API direct:

```text
Client → HTTPS e-commerce-ndt.test:443 → ALB
local certificate/key → ACM imported certificate → ALB listener
```

Certificate imported có thể là self-signed hoặc do private CA cấp. ACM chỉ lưu và cung cấp
certificate cho consumer; ACM không biến certificate này thành public-trusted certificate.

## Resources

| Resource | Vai trò |
|---|---|
| `aws_acm_certificate.alb` | Import certificate body và private key vào ACM |
| `local.name` | Tạo tên và tag theo project/environment |

Module không tạo ALB, listener, DNS record, Route 53 hosted zone, public CA, CloudFront
distribution hoặc CloudFront viewer certificate.

## Local certificate workflow

Tạo certificate cho hostname local bằng script:

```bash
ALB_CERT_DOMAIN=e-commerce-ndt.test \
  bash scripts/generate-alb-self-signed-cert.sh environments/dev/local-certs
```

Script tạo:

```text
environments/dev/local-certs/alb.crt.pem
environments/dev/local-certs/alb.key.pem
```

Certificate phải có SAN `DNS:e-commerce-ndt.test`. Private key không mã hóa nên phải giữ
quyền truy cập hạn chế và không được commit vào Git.

## Environment wiring

Root module `environments/dev` nối module này với ALB:

```hcl
module "alb_imported_certificate" {
  count  = var.enable_alb_https_test ? 1 : 0
  source = "../../modules/certificates-imported"

  project_name = var.project_name
  environment  = var.environment

  certificate_file    = var.alb_https_certificate_file
  private_key_file    = var.alb_https_private_key_file
  certificate_version = var.alb_https_certificate_version
}
```

ARN `certificate_arn` được truyền vào `modules/alb` để tạo listener HTTPS port `443`.
Module chỉ được tạo khi `enable_alb_https_test = true`.

## Inputs

| Input | Bắt buộc | Mục đích |
|---|---:|---|
| `project_name` | Có | Prefix tên resource và tag |
| `environment` | Có | Suffix môi trường |
| `certificate_file` | Có | Path local tới PEM certificate body |
| `private_key_file` | Có | Path local tới unencrypted PEM private key |
| `certificate_version` | Không | Version tăng dần để trigger re-import khi rotate |

Ví dụ environment input:

```hcl
alb_https_certificate_file    = "local-certs/alb.crt.pem"
alb_https_private_key_file    = "local-certs/alb.key.pem"
alb_https_certificate_version = 2
```

## Output

| Output | Consumer |
|---|---|
| `certificate_arn` | ALB HTTPS listener `443` |

## Trust và DNS trên client

ACM import không làm browser tự trust self-signed certificate. Máy client phải trust
certificate, ví dụ Debian/Ubuntu:

```bash
sudo cp environments/dev/local-certs/alb.crt.pem \
  /usr/local/share/ca-certificates/ecommerce-alb.crt
sudo update-ca-certificates
```

`e-commerce-ndt.test` là local hostname, không có public DNS. Dùng `curl --resolve`,
`dnsmasq` hoặc local DNS resolver để hostname trỏ tới ALB. Không gọi bằng ALB DNS name vì
hostname đó không khớp SAN của certificate.

## Rotation và security boundary

- Imported certificate không được ACM tự động renew.
- Khi rotate, tạo certificate/key mới và tăng `certificate_version`.
- Không commit private key, `.tfvars`, password hoặc Terraform state.
- `certificate_file` và `private_key_file` là path local; file phải tồn tại trước `plan`.
- Không dùng self-signed imported certificate cho public CloudFront viewer TLS.

## Validation

```bash
openssl x509 -in environments/dev/local-certs/alb.crt.pem \
  -noout -subject -issuer -dates -ext subjectAltName

terraform fmt -check -recursive
terraform -chdir=environments/dev validate
```
