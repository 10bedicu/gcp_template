#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/helm_charts/care_metrics_exporter"
RENDERED="$(mktemp)"
OVERRIDE_RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED" "$OVERRIDE_RENDERED"' EXIT

helm lint "$CHART"
helm template care-metrics-exporter "$CHART" --namespace care-test > "$RENDERED"
helm template care-metrics-exporter "$CHART" \
  --namespace care-test \
  --set image.repository=ghcr.io/example/care-metrics-exporter \
  --set image.tag=0123456789abcdef0123456789abcdef01234567 \
  --set-string podAnnotations.checksum/broker-secret=testchecksum \
  > "$OVERRIDE_RENDERED"

assert_contains() {
  local expected="$1"
  grep -Fq -- "$expected" "$RENDERED" || {
    printf 'missing rendered text: %s\n' "$expected" >&2
    exit 1
  }
}

assert_not_contains() {
  local unexpected="$1"
  if grep -Fq -- "$unexpected" "$RENDERED"; then
    printf 'unexpected rendered text: %s\n' "$unexpected" >&2
    exit 1
  fi
}

assert_contains 'kind: Deployment'
assert_contains 'kind: Service'
assert_contains 'kind: PodMonitoring'
assert_contains 'image: "ghcr.io/jesbinjoseph/care-metrics-exporter:8ab2445d7cf88e6f335f1d951062c1b6f9df9a3d"'
assert_contains 'name: CELERY_BROKER_URL'
assert_contains 'key: CELERY_BROKER_URL'
assert_contains 'name: CELERY_QUEUES'
assert_contains 'value: "celery"'
assert_contains 'name: LOG_LEVEL'
assert_contains 'value: "INFO"'
assert_contains 'automountServiceAccountToken: false'
assert_contains 'readOnlyRootFilesystem: true'
assert_contains 'runAsNonRoot: true'
assert_contains 'cpu: 5m'
assert_contains 'memory: 48Mi'
assert_contains 'cpu: 50m'
assert_contains 'memory: 64Mi'
assert_contains 'path: /metrics'
assert_contains 'interval: 30s'
assert_not_contains 'kind: ServiceMonitor'
assert_not_contains 'CELERY_REDIS_PRIORITY_STEPS'
assert_not_contains 'REDIS_SOCKET_TIMEOUT_SECONDS'
assert_not_contains 'COLLECTION_LOCK_TIMEOUT_SECONDS'

grep -Fq -- 'image: "ghcr.io/example/care-metrics-exporter:0123456789abcdef0123456789abcdef01234567"' "$OVERRIDE_RENDERED"
grep -Fq -- 'checksum/broker-secret: testchecksum' "$OVERRIDE_RENDERED"
