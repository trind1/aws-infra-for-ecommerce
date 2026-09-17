#!/usr/bin/env bash

set -euo pipefail

certificate_domain="${ALB_CERT_DOMAIN:-e-commerce-ndt.test}"
output_dir="${1:-local-certs}"

mkdir -p "$output_dir"
umask 077

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -sha256 \
  -nodes \
  -days 30 \
  -keyout "$output_dir/alb.key.pem" \
  -out "$output_dir/alb.crt.pem" \
  -subj "/CN=$certificate_domain" \
  -addext "subjectAltName=DNS:$certificate_domain" \
  -addext "extendedKeyUsage=serverAuth"

cat <<EOF
Generated:
  certificate: $output_dir/alb.crt.pem
  private key: $output_dir/alb.key.pem
  domain:      $certificate_domain

For local trust on Debian/Ubuntu, install the certificate on the test client:
  sudo cp "$output_dir/alb.crt.pem" /usr/local/share/ca-certificates/ecommerce-alb.crt
  sudo update-ca-certificates

The private key is unencrypted and must not be committed.
EOF
