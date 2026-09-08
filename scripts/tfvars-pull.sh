#!/usr/bin/env bash
# tfvars-pull.sh — Pull tfvars payload from GCP Secret Manager.
#
# Fetches the latest secret version, shows a diff against the local file,
# asks for confirmation, then overwrites the local file.
#
# The diff is hidden when CI=true (GitHub Actions sets this) so secret
# values never land in CI logs; it is shown on local machines.
#
# Usage:
#   ./scripts/tfvars-pull.sh --project=PROJECT_ID --env=ENV [--out=FILE] \
#       [--secret=SECRET_NAME]
#
# Defaults:
#   secret name: tofu-tfvars-{env}
#   output file: /tmp/.tofu-{env}.tfvars

set -euo pipefail

PROJECT_ID=""
ENV_NAME=""
OUT_FILE=""
SECRET_NAME=""

usage() {
  echo "Usage: $0 --project=PROJECT_ID --env=ENV [--out=FILE] [--secret=SECRET_NAME]"
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --project=*) PROJECT_ID="${arg#*=}" ;;
    --env=*)     ENV_NAME="${arg#*=}" ;;
    --out=*)     OUT_FILE="${arg#*=}" ;;
    --secret=*)  SECRET_NAME="${arg#*=}" ;;
    -h|--help)   usage ;;
    *)           echo "Unknown argument: $arg"; usage ;;
  esac
done

[[ -n "$PROJECT_ID" ]] || { echo "ERROR: --project is required"; usage; }
[[ -n "$ENV_NAME" ]]   || { echo "ERROR: --env is required"; usage; }

[[ -n "$SECRET_NAME" ]] || SECRET_NAME="tofu-tfvars-${ENV_NAME}"
[[ -n "$OUT_FILE" ]]    || OUT_FILE="/tmp/.tofu-${ENV_NAME}.tfvars"

echo "Pulling tfvars from secret '$SECRET_NAME' (project: $PROJECT_ID)..."

umask 077
TMP_REMOTE="$(mktemp)"
trap 'rm -f "$TMP_REMOTE"' EXIT

gcloud secrets versions access latest \
  --secret="$SECRET_NAME" \
  --project="$PROJECT_ID" > "$TMP_REMOTE"

if [[ -f "$OUT_FILE" ]] && cmp -s "$OUT_FILE" "$TMP_REMOTE"; then
  echo "Already up-to-date — local file matches remote."
  exit 0
fi

LOCAL_FOR_DIFF="$OUT_FILE"
[[ -f "$OUT_FILE" ]] || LOCAL_FOR_DIFF="/dev/null"

if [[ "${CI:-}" == "true" ]]; then
  echo "Local file differs from remote (diff hidden: CI=true)."
else
  echo ""
  echo "Diff (local → remote):"
  diff -u --label "local:  $OUT_FILE" --label "remote: $SECRET_NAME" "$LOCAL_FOR_DIFF" "$TMP_REMOTE" || true
  echo ""
fi

if [[ "${CI:-}" != "true" ]]; then
  printf "Overwrite %s with the remote version? [y/N] " "$OUT_FILE"
  read -r CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

cp "$TMP_REMOTE" "$OUT_FILE"
echo "Wrote tfvars to: $OUT_FILE"
