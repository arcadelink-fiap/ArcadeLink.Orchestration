#!/usr/bin/env bash
set -euo pipefail

RABBITMQ_HOST="${RABBITMQ_HOST:-localhost}"
RABBITMQ_MGMT_PORT="${RABBITMQ_MGMT_PORT:-15672}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-guest}"
BASE_URL="http://${RABBITMQ_HOST}:${RABBITMQ_MGMT_PORT}/api"

declare_queue_and_binding() {
  local queue="$1"
  local exchange="$2"

  curl -sf -u "${RABBITMQ_USER}:${RABBITMQ_PASSWORD}" \
    -X PUT "${BASE_URL}/queues/%2f/${queue}" \
    -H "content-type: application/json" \
    -d '{"durable": true}'

  curl -sf -u "${RABBITMQ_USER}:${RABBITMQ_PASSWORD}" \
    -X POST "${BASE_URL}/bindings/%2f/e/${exchange}/q/${queue}" \
    -H "content-type: application/json" \
    -d '{}'

  echo "Fila '${queue}' criada e vinculada ao exchange '${exchange}'."
}

declare_queue_and_binding "function-user-created-event" "ArcadeLink.Contracts:UserCreatedEvent"
declare_queue_and_binding "function-payment-processed-event" "ArcadeLink.Contracts:PaymentProcessedEvent"
