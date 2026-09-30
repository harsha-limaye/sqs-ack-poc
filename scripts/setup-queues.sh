#!/usr/bin/env bash
# Creates the two test queues (+ DLQs) in LocalStack with a short visibility timeout
# so redelivery behaviour can be observed quickly.
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

ENDPOINT="http://localhost:4566"
VISIBILITY_TIMEOUT=5
MAX_RECEIVE_COUNT=2

aws_cmd() {
  aws --endpoint-url "$ENDPOINT" "$@"
}

create_queue_with_dlq() {
  local name="$1"
  local dlq_name="${name}-dlq"

  echo "Creating DLQ: ${dlq_name}"
  dlq_url=$(aws_cmd sqs create-queue --queue-name "${dlq_name}" --query 'QueueUrl' --output text)
  dlq_arn=$(aws_cmd sqs get-queue-attributes --queue-url "${dlq_url}" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)

  echo "Creating queue: ${name} (visibilityTimeout=${VISIBILITY_TIMEOUT}s, maxReceiveCount=${MAX_RECEIVE_COUNT}, dlq=${dlq_arn})"
  redrive_policy_json=$(python3 -c "
import json
print(json.dumps(json.dumps({'deadLetterTargetArn': '${dlq_arn}', 'maxReceiveCount': '${MAX_RECEIVE_COUNT}'})))
")

  attrs_file=$(mktemp)
  cat > "${attrs_file}" <<EOF
{
  "VisibilityTimeout": "${VISIBILITY_TIMEOUT}",
  "RedrivePolicy": ${redrive_policy_json}
}
EOF

  aws_cmd sqs create-queue --queue-name "${name}" --attributes "file://${attrs_file}" > /dev/null
  rm -f "${attrs_file}"

  echo "Queue ${name} ready."
}

create_queue_with_dlq "async-fire-and-forget-queue"
create_queue_with_dlq "sync-blocking-queue"

echo ""
echo "All queues created. Listing:"
aws_cmd sqs list-queues
