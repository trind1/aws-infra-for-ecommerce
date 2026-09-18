#!/usr/bin/env bash

set -euo pipefail

# Run this script once, after terraform apply, from the repository root.
# It deliberately targets one healthy ASG instance through SSM instead of
# running migration from user_data on every instance.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly TERRAFORM_DIR="${REPO_ROOT}/environments/dev"
readonly WAIT_TIMEOUT_SECONDS="${MIGRATION_WAIT_TIMEOUT_SECONDS:-900}"
readonly POLL_INTERVAL_SECONDS="${MIGRATION_POLL_INTERVAL_SECONDS:-10}"

if ! [[ "${WAIT_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] || (( WAIT_TIMEOUT_SECONDS < 1 )); then
  echo "MIGRATION_WAIT_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 1
fi

if ! [[ "${POLL_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || (( POLL_INTERVAL_SECONDS < 1 )); then
  echo "MIGRATION_POLL_INTERVAL_SECONDS must be a positive integer." >&2
  exit 1
fi

command -v aws >/dev/null 2>&1 || {
  echo "AWS CLI is required." >&2
  exit 1
}

command -v terraform >/dev/null 2>&1 || {
  echo "Terraform is required." >&2
  exit 1
}

ASG_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw autoscaling_group_name)"

if [[ -z "${ASG_NAME}" ]]; then
  echo "autoscaling_group_name Terraform output is empty." >&2
  exit 1
fi

echo "Waiting for a healthy, SSM-managed instance in ${ASG_NAME}..."

INSTANCE_ID=""
deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

while (( SECONDS < deadline )); do
  candidate="$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${ASG_NAME}" \
    --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`].InstanceId | [0]' \
    --output text 2>/dev/null || true)"

  if [[ -n "${candidate}" && "${candidate}" != "None" ]]; then
    ping_status="$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=${candidate}" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || true)"

    if [[ "${ping_status}" == "Online" ]]; then
      INSTANCE_ID="${candidate}"
      break
    fi
  fi

  sleep "${POLL_INTERVAL_SECONDS}"
done

if [[ -z "${INSTANCE_ID}" ]]; then
  echo "Timed out waiting for a healthy SSM-managed instance." >&2
  exit 1
fi

echo "Running Prisma migration once on ${INSTANCE_ID}."

COMMAND_ID="$(aws ssm send-command \
  --instance-ids "${INSTANCE_ID}" \
  --document-name AWS-RunShellScript \
  --comment "Run Prisma migration once for dev" \
  --parameters '{"commands":["docker inspect --format={{.State.Running}} nodejs-api | grep -qx true","docker exec nodejs-api npm run db:deploy"]}' \
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
  echo "Database migration failed with status: ${status}" >&2
  exit 1
fi

echo "Database migration completed successfully on ${INSTANCE_ID}."
