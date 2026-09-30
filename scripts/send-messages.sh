#!/usr/bin/env bash
# Sends one test message to each of the two queues.
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

ENDPOINT="http://localhost:4566"

aws_cmd() {
  aws --endpoint-url "$ENDPOINT" "$@"
}

send_to() {
  local name="$1"
  local url
  url=$(aws_cmd sqs get-queue-url --queue-name "${name}" --query 'QueueUrl' --output text)
  local body="test-message-$(date +%s)"
  aws_cmd sqs send-message --queue-url "${url}" --message-body "${body}" > /dev/null
  echo "Sent '${body}' to ${name}"
}

send_to "async-fire-and-forget-queue"
send_to "sync-blocking-queue"
