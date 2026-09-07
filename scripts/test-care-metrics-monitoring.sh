#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/deploy/monitoring.tf"

assert_contains() {
  local expected="$1"
  grep -Fq -- "$expected" "$FILE" || {
    printf 'missing monitoring configuration: %s\n' "$expected" >&2
    exit 1
  }
}

test -f "$FILE"
assert_contains 'resource "google_monitoring_dashboard" "care_metrics_exporter"'
assert_contains 'resource "google_monitoring_notification_channel" "email"'
assert_contains 'resource "google_monitoring_alert_policy" "care_queue_length"'
assert_contains 'for_each = var.monitoring_notification_emails'
assert_contains 'celery_queue_length'
assert_contains '> 250'
assert_contains 'duration            = "300s"'
assert_contains 'max by (queue)'
