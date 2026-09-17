# Certificate configuration

## Kiến trúc certificate

Environment `dev` dùng hai cơ chế khác nhau:

```text
CloudFront default domain → AWS-managed CloudFront certificate
ALB e-commerce-ndt.test  → local self-signed certificate imported vào ACM
```

## ALB test certificate

Certificate được generate trên máy local, có SAN:

```text
DNS:e-commerce-ndt.test
```

Tạo certificate:

```bash
ALB_CERT_DOMAIN=e-commerce-ndt.test \
  bash scripts/generate-alb-self-signed-cert.sh environments/dev/local-certs
```

Sau đó truyền path certificate và private key qua ignored local `.tfvars`. Không commit
private key hoặc nội dung certificate vào repository. Tăng `certificate_version` khi
rotate certificate để Terraform nhận biết private key mới.

## Trust và local DNS

- Máy client phải trust certificate trước khi browser gọi API.
- `e-commerce-ndt.test` không phải public domain; cần local DNS, `dnsmasq`, hoặc
  `curl --resolve` để trỏ tới ALB.
- `/etc/hosts` chỉ phù hợp tạm thời vì IP của ALB có thể thay đổi.

## Boundary

Module `certificates-imported` chỉ import PEM vào ACM và xuất ARN cho ALB. Nó không tạo
Route 53, hosted zone, public certificate, CloudFront certificate hoặc DNS record.
Imported certificate không được ACM tự động renew.

## Checklist

| Hạng mục | Trạng thái |
|---|---|
| Script generate local certificate | Implemented |
| ACM imported certificate module | Implemented, chưa apply |
| ALB listener wiring | Implemented, chưa apply |
| Local trust store | Ngoài Terraform, cần thực hiện trên client |
| Local DNS resolver | Ngoài Terraform, cần thực hiện trên client |
| Public certificate cho CloudFront custom domain | Not in scope của dev |
