#!/usr/bin/env bash
# Polls queue + DLQ depths every 2s for ~30s so you can watch ack/redelivery behaviour live.
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

ENDPOINT="http://localhost:4566"

aws_cmd() {
  aws --endpoint-url "$ENDPOINT" "$@"
}

depth() {
  local name="$1"
  local url
  url=$(aws_cmd sqs get-queue-url --queue-name "${name}" --query 'QueueUrl' --output text 2>/dev/null) || { echo "?"; return; }
  aws_cmd sqs get-queue-attributes --queue-url "${url}" \
    --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
    --query 'Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible]' \
    --output text 2>/dev/null | tr '\t' '/' || echo "?"
}

for i in $(seq 1 15); do
  printf "%2ds  async-queue(visible/in-flight)=%-8s async-dlq=%-8s | sync-queue(visible/in-flight)=%-8s sync-dlq=%-8s\n" \
    "$((i*2))" \
    "$(depth async-fire-and-forget-queue)" \
    "$(depth async-fire-and-forget-queue-dlq)" \
    "$(depth sync-blocking-queue)" \
    "$(depth sync-blocking-queue-dlq)"
  sleep 2
done
