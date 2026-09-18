#!/usr/bin/env bash

set -euo pipefail

# Run once after scripts/run-db-migration.sh succeeds.
# Credentials can be read from a local, chmod 600 env file and are sent to one
# SSM-managed instance. The env file is never copied into the Docker image.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly TERRAFORM_DIR="${REPO_ROOT}/environments/dev"
readonly POLL_INTERVAL_SECONDS="${ADMIN_PROVISION_POLL_INTERVAL_SECONDS:-10}"

admin_env_file=""
while (($# > 0)); do
  case "$1" in
    --env-file)
      if (($# < 2)); then
        echo "--env-file requires a path." >&2
        exit 1
      fi
      admin_env_file="$2"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: %s [--env-file PATH]\n' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

command -v aws >/dev/null 2>&1 || {
  echo "AWS CLI is required." >&2
  exit 1
}

command -v terraform >/dev/null 2>&1 || {
  echo "Terraform is required." >&2
  exit 1
}

if [[ -n "${admin_env_file}" ]]; then
  if [[ ! -f "${admin_env_file}" || ! -r "${admin_env_file}" ]]; then
    echo "Admin env file does not exist or is not readable: ${admin_env_file}" >&2
    exit 1
  fi

  file_mode="$(stat -c '%a' "${admin_env_file}")"
  if [[ "${file_mode}" != "600" ]]; then
    echo "Admin env file must have mode 600: chmod 600 ${admin_env_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "${admin_env_file}"
  set +a
else
  read -r -p "Admin email: " ADMIN_EMAIL
  read -r -s -p "Admin password: " ADMIN_PASSWORD
  printf '\n'
  read -r -s -p "Admin provision token: " ADMIN_PROVISION_TOKEN
  printf '\n'
  read -r -s -p "Admin provision token hash: " ADMIN_PROVISION_TOKEN_HASH
  printf '\n'
fi

admin_email="${ADMIN_EMAIL:-}"
admin_password="${ADMIN_PASSWORD:-}"
admin_display_name="${ADMIN_DISPLAY_NAME:-Administrator}"
admin_provision_token="${ADMIN_PROVISION_TOKEN:-}"
admin_provision_token_hash="${ADMIN_PROVISION_TOKEN_HASH:-}"

if [[ -z "${admin_email}" || -z "${admin_password}" || -z "${admin_provision_token}" || -z "${admin_provision_token_hash}" ]]; then
  echo "Admin email, password, provision token and token hash are required." >&2
  exit 1
fi

if ! [[ "${POLL_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || (( POLL_INTERVAL_SECONDS < 1 )); then
  echo "ADMIN_PROVISION_POLL_INTERVAL_SECONDS must be a positive integer." >&2
  exit 1
fi

encode_value() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

ASG_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw autoscaling_group_name)"

if [[ -z "${ASG_NAME}" ]]; then
  echo "autoscaling_group_name Terraform output is empty." >&2
  exit 1
fi

INSTANCE_ID="$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${ASG_NAME}" \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`].InstanceId | [0]' \
  --output text)"

if [[ -z "${INSTANCE_ID}" || "${INSTANCE_ID}" == "None" ]]; then
  echo "No healthy instance is available in ${ASG_NAME}." >&2
  exit 1
fi

ping_status="$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text)"

if [[ "${ping_status}" != "Online" ]]; then
  echo "Instance ${INSTANCE_ID} is not SSM Online: ${ping_status}" >&2
  exit 1
fi

email_b64="$(encode_value "${admin_email}")"
password_b64="$(encode_value "${admin_password}")"
token_b64="$(encode_value "${admin_provision_token}")"
token_hash_b64="$(encode_value "${admin_provision_token_hash}")"
display_name_b64="$(encode_value "${admin_display_name}")"

remote_commands=(
  "set -eu; umask 077; mkdir -p /opt/ecommerce; rm -f /tmp/ecommerce-admin.* /opt/ecommerce/admin-provision.env; trap 'shred -u /opt/ecommerce/admin-provision.env /tmp/ecommerce-admin.* 2>/dev/null || rm -f /opt/ecommerce/admin-provision.env /tmp/ecommerce-admin.*' EXIT"
  "printf '%s' '${email_b64}' | base64 -d > /tmp/ecommerce-admin.email"
  "printf '%s' '${password_b64}' | base64 -d > /tmp/ecommerce-admin.password"
  "printf '%s' '${display_name_b64}' | base64 -d > /tmp/ecommerce-admin.display-name"
  "printf '%s' '${token_b64}' | base64 -d > /tmp/ecommerce-admin.token"
  "printf '%s' '${token_hash_b64}' | base64 -d > /tmp/ecommerce-admin.token-hash"
  "docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' nodejs-api | sed -n 's/^DATABASE_URL=//p' | head -n 1 > /tmp/ecommerce-admin.database-url"
  "test -s /tmp/ecommerce-admin.database-url"
  "printf 'DATABASE_URL=' > /opt/ecommerce/admin-provision.env; cat /tmp/ecommerce-admin.database-url >> /opt/ecommerce/admin-provision.env; printf '\\nADMIN_EMAIL=' >> /opt/ecommerce/admin-provision.env; cat /tmp/ecommerce-admin.email >> /opt/ecommerce/admin-provision.env; printf '\\nADMIN_PASSWORD=' >> /opt/ecommerce/admin-provision.env; cat /tmp/ecommerce-admin.password >> /opt/ecommerce/admin-provision.env; printf '\\nADMIN_DISPLAY_NAME=' >> /opt/ecommerce/admin-provision.env; cat /tmp/ecommerce-admin.display-name >> /opt/ecommerce/admin-provision.env; printf '\\nADMIN_PROVISION_TOKEN_HASH=' >> /opt/ecommerce/admin-provision.env; cat /tmp/ecommerce-admin.token-hash >> /opt/ecommerce/admin-provision.env; printf '\\nADMIN_PROVISION_TOKEN=' >> /opt/ecommerce/admin-provision.env; cat /tmp/ecommerce-admin.token >> /opt/ecommerce/admin-provision.env; printf '\\n' >> /opt/ecommerce/admin-provision.env; chmod 600 /opt/ecommerce/admin-provision.env"
  "image=\$(docker inspect --format '{{.Config.Image}}' nodejs-api); test -n \"\$image\"; docker run --rm --env-file /opt/ecommerce/admin-provision.env \$image node apps/api/dist/auth/provision-admin.js"
)

command_list="$(IFS=,; printf '%s' "${remote_commands[*]}")"

echo "Provisioning admin once on ${INSTANCE_ID}."

COMMAND_ID="$(aws ssm send-command \
  --instance-ids "${INSTANCE_ID}" \
  --document-name AWS-RunShellScript \
  --comment "Provision ecommerce admin once for dev" \
  --parameters "commands=${command_list}" \
  --query 'Command.CommandId' \
  --output text)"

status=""
while true; do
  status="$(aws ssm get-command-invocation \
    --command-id "${COMMAND_ID}" \
    --instance-id "${INSTANCE_ID}" \
    --query 'Status' \
    --output text)"

  case "${status}" in
    Pending|InProgress|Delayed)
      sleep "${POLL_INTERVAL_SECONDS}"
      ;;
    *)
      break
      ;;
  esac
done

aws ssm get-command-invocation \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}'

if [[ "${status}" != "Success" ]]; then
  echo "Admin provisioning failed with status: ${status}." >&2
  exit 1
fi

echo "Admin provisioning completed successfully."
