#!/usr/bin/env bash
# tfvars-push.sh — Push tfvars payload as a new Secret Manager version.
#
# Shows a diff between the local file and the remote secret, asks for
# confirmation, then uploads a new version.
#
# The diff is hidden when CI=true (GitHub Actions sets this) so secret
# values never land in CI logs; it is shown on local machines.
#
# Usage:
#   ./scripts/tfvars-push.sh --project=PROJECT_ID --env=ENV --file=PATH \
#       [--secret=SECRET_NAME] [--yes]
#
# Defaults:
#   secret name: tofu-tfvars-{env}
#
# The only guard is that project_id inside the file must match --project,
# to prevent pushing one project's tfvars into another.

set -euo pipefail

PROJECT_ID=""
ENV_NAME=""
TFVARS_FILE=""
SECRET_NAME=""
YES=false

MAX_VERSIONS=10
DEFAULT_REGION="asia-south1" # matches variables.tf default

usage() {
  echo "Usage: $0 --project=PROJECT_ID --env=ENV --file=PATH [--secret=SECRET_NAME] [--yes]"
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    --project=*) PROJECT_ID="${arg#*=}" ;;
    --env=*)     ENV_NAME="${arg#*=}" ;;
    --file=*)    TFVARS_FILE="${arg#*=}" ;;
    --secret=*)  SECRET_NAME="${arg#*=}" ;;
    --yes|-y)    YES=true ;;
    -h|--help)   usage ;;
    *)           echo "Unknown argument: $arg"; usage ;;
  esac
done

[[ -n "$PROJECT_ID" ]]  || { echo "ERROR: --project is required"; usage; }
[[ -n "$ENV_NAME" ]]    || { echo "ERROR: --env is required"; usage; }
[[ -n "$TFVARS_FILE" ]] || { echo "ERROR: --file is required"; usage; }
[[ -f "$TFVARS_FILE" ]] || { echo "ERROR: File not found: $TFVARS_FILE"; exit 1; }

[[ -n "$SECRET_NAME" ]] || SECRET_NAME="tofu-tfvars-${ENV_NAME}"

# ── Safety check: project_id alignment ───────────────────────────────────

TFVARS_PROJECT_ID="$(
  grep -E '^[[:space:]]*project_id[[:space:]]*=' "$TFVARS_FILE" \
    | head -n1 \
    | sed -E 's/^[[:space:]]*project_id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
)"

if [[ -z "$TFVARS_PROJECT_ID" ]]; then
  echo "ERROR: Could not find 'project_id = \"...\"' in $TFVARS_FILE."
  echo "       Refusing to push without verifying project alignment."
  exit 1
fi

if [[ "$TFVARS_PROJECT_ID" != "$PROJECT_ID" ]]; then
  echo "ERROR: project_id mismatch — refusing to push."
  echo "       --project argument : $PROJECT_ID"
  echo "       project_id in file : $TFVARS_PROJECT_ID  ($TFVARS_FILE)"
  exit 1
fi

# ── Format ───────────────────────────────────────────────────────────────

echo "Formatting tfvars..."
tofu fmt "$TFVARS_FILE" >/dev/null

# ── Check remote state and show diff ─────────────────────────────────────

SECRET_EXISTS=true
if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  SECRET_EXISTS=false
fi

umask 077
TMP_REMOTE="$(mktemp)"
trap 'rm -f "$TMP_REMOTE"' EXIT

if [[ "$SECRET_EXISTS" == "true" ]]; then
  gcloud secrets versions access latest \
    --secret="$SECRET_NAME" \
    --project="$PROJECT_ID" > "$TMP_REMOTE"

  if cmp -s "$TFVARS_FILE" "$TMP_REMOTE"; then
    echo "No changes to push — local file matches remote."
    exit 0
  fi

  if [[ "${CI:-}" == "true" ]]; then
    echo "Local file differs from remote (diff hidden: CI=true)."
  else
    echo ""
    echo "Diff (remote → local):"
    diff -u --label "remote: $SECRET_NAME" --label "local:  $TFVARS_FILE" "$TMP_REMOTE" "$TFVARS_FILE" || true
    echo ""
  fi
else
  echo "Secret '$SECRET_NAME' does not exist. Will create it."
fi

# ── Confirmation prompt ──────────────────────────────────────────────────

if [[ "$YES" != "true" && "${CI:-}" != "true" ]]; then
  printf "Push tfvars to secret '%s' in project '%s'? [y/N] " "$SECRET_NAME" "$PROJECT_ID"
  read -r CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# ── Create secret if needed ──────────────────────────────────────────────

if [[ "$SECRET_EXISTS" != "true" ]]; then
  TFVARS_REGION="$(
    grep -E '^[[:space:]]*region[[:space:]]*=' "$TFVARS_FILE" \
      | head -n1 \
      | sed -E 's/^[[:space:]]*region[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
  )"
  TFVARS_REGION="${TFVARS_REGION:-$DEFAULT_REGION}"

  echo "Creating secret '$SECRET_NAME' (project: $PROJECT_ID, location: $TFVARS_REGION)..."
  gcloud secrets create "$SECRET_NAME" \
    --project="$PROJECT_ID" \
    --replication-policy=user-managed \
    --locations="$TFVARS_REGION"
fi

# ── Upload ───────────────────────────────────────────────────────────────

echo "Uploading tfvars to project '$PROJECT_ID'..."
gcloud secrets versions add "$SECRET_NAME" \
  --project="$PROJECT_ID" \
  --data-file="$TFVARS_FILE" >/dev/null

# ── Prune old versions — keep only the MAX_VERSIONS most recent ──────────

echo "Pruning old versions (keeping $MAX_VERSIONS most recent)..."
gcloud secrets versions list "$SECRET_NAME" \
  --project="$PROJECT_ID" \
  --filter="state=enabled" \
  --format="value(name)" \
  --sort-by=~createTime \
  | tail -n +$((MAX_VERSIONS + 1)) \
  | while read -r version; do
      [[ -z "$version" ]] && continue
      echo "  Destroying version $version..."
      gcloud secrets versions destroy "$version" \
        --secret="$SECRET_NAME" \
        --project="$PROJECT_ID" --quiet
    done

echo "OK: tfvars pushed for secret '$SECRET_NAME' (project: $PROJECT_ID)."
