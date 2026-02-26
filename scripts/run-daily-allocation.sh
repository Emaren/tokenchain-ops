#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:3321}"
ADMIN_API_TOKEN="${ADMIN_API_TOKEN:-}"
DATE="${DATE:-}"
TOTAL_BUCKET_C_AMOUNT="${TOTAL_BUCKET_C_AMOUNT:-}"
ALLOCATION_MODE="${ALLOCATION_MODE:-auto}"
ALLOCATION_ITEMS_JSON="${ALLOCATION_ITEMS_JSON:-[]}"
MIN_ACTIVITY_SCORE="${MIN_ACTIVITY_SCORE:-1}"
MAX_AUTO_TOKENS="${MAX_AUTO_TOKENS:-200}"
ALLOW_OVERWRITE="${ALLOW_OVERWRITE:-false}"
DRY_RUN="${DRY_RUN:-false}"

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required binary: $1" >&2
    exit 1
  fi
}

to_bool_json() {
  case "${1,,}" in
    true|1|yes|y|on) echo "true" ;;
    false|0|no|n|off|"") echo "false" ;;
    *)
      echo "ERROR: invalid boolean value '$1'" >&2
      exit 1
      ;;
  esac
}

require_bin curl
require_bin jq

if [[ -z "${ADMIN_API_TOKEN}" ]]; then
  echo "ERROR: ADMIN_API_TOKEN is required" >&2
  exit 1
fi

if [[ ! "${TOTAL_BUCKET_C_AMOUNT}" =~ ^[0-9]+$ ]] || [[ "${TOTAL_BUCKET_C_AMOUNT}" == "0" ]]; then
  echo "ERROR: TOTAL_BUCKET_C_AMOUNT must be a positive integer" >&2
  exit 1
fi

if [[ ! "${MIN_ACTIVITY_SCORE}" =~ ^[0-9]+$ ]] || [[ "${MIN_ACTIVITY_SCORE}" == "0" ]]; then
  echo "ERROR: MIN_ACTIVITY_SCORE must be a positive integer" >&2
  exit 1
fi
if [[ ! "${MAX_AUTO_TOKENS}" =~ ^[0-9]+$ ]] || [[ "${MAX_AUTO_TOKENS}" == "0" ]]; then
  echo "ERROR: MAX_AUTO_TOKENS must be a positive integer" >&2
  exit 1
fi

allow_overwrite_json="$(to_bool_json "${ALLOW_OVERWRITE}")"
dry_run_json="$(to_bool_json "${DRY_RUN}")"

case "${ALLOCATION_MODE,,}" in
  auto)
    payload="$(
      jq -n \
        --arg date "${DATE}" \
        --argjson total_bucket_c_amount "${TOTAL_BUCKET_C_AMOUNT}" \
        --argjson min_activity_score "${MIN_ACTIVITY_SCORE}" \
        --argjson max_auto_tokens "${MAX_AUTO_TOKENS}" \
        --argjson allow_overwrite "${allow_overwrite_json}" \
        --argjson dry_run "${dry_run_json}" \
        '{
          date: $date,
          total_bucket_c_amount: $total_bucket_c_amount,
          auto_from_verified_tokens: true,
          min_activity_score: $min_activity_score,
          max_auto_tokens: $max_auto_tokens,
          allow_overwrite: $allow_overwrite,
          dry_run: $dry_run
        }'
    )"
    ;;
  manual)
    if ! echo "${ALLOCATION_ITEMS_JSON}" | jq -e 'type == "array" and length > 0' >/dev/null; then
      echo "ERROR: ALLOCATION_ITEMS_JSON must be a non-empty JSON array in manual mode" >&2
      exit 1
    fi
    payload="$(
      jq -n \
        --arg date "${DATE}" \
        --argjson total_bucket_c_amount "${TOTAL_BUCKET_C_AMOUNT}" \
        --argjson items "${ALLOCATION_ITEMS_JSON}" \
        --argjson allow_overwrite "${allow_overwrite_json}" \
        --argjson dry_run "${dry_run_json}" \
        '{
          date: $date,
          total_bucket_c_amount: $total_bucket_c_amount,
          auto_from_verified_tokens: false,
          items: $items,
          allow_overwrite: $allow_overwrite,
          dry_run: $dry_run
        }'
    )"
    ;;
  *)
    echo "ERROR: ALLOCATION_MODE must be 'auto' or 'manual'" >&2
    exit 1
    ;;
esac

tmp_body="$(mktemp)"
trap 'rm -f "${tmp_body}"' EXIT

http_code="$(
  curl -sS \
    -o "${tmp_body}" \
    -w "%{http_code}" \
    -X POST "${API_BASE}/v1/admin/loyalty/daily-allocation/run" \
    -H "content-type: application/json" \
    -H "authorization: Bearer ${ADMIN_API_TOKEN}" \
    --data "${payload}"
)"

cat "${tmp_body}"
echo

if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
  echo "ERROR: daily allocation run failed with HTTP ${http_code}" >&2
  exit 1
fi

if ! jq -e '.ok == true' "${tmp_body}" >/dev/null; then
  echo "ERROR: daily allocation response returned ok=false" >&2
  exit 1
fi

echo "Daily allocation run completed (HTTP ${http_code})."
