#!/bin/bash
set -euo pipefail

ENV_FILE="${SRCROOT}/.env"
OUT_DIR="${SRCROOT}/bilingual reader watch flashcard Watch App"
OUT_FILE="${OUT_DIR}/GeneratedEnv.swift"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "error: missing .env at ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
# Read KEY=VALUE lines, ignore comments/blank
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
  export "${line?}"
done < "${ENV_FILE}"
set +a

if [[ -z "${GET_ON_LOAD_DATA_URL:-}" ]]; then
  echo "error: GET_ON_LOAD_DATA_URL is not set in .env" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
cat > "${OUT_FILE}" <<EOF
// Generated from .env — do not edit by hand.
// Regenerate via Scripts/generate-env.sh (Xcode build phase).

import Foundation

enum GeneratedEnv {
    static let getOnLoadDataURL = URL(string: "${GET_ON_LOAD_DATA_URL}")!
}
EOF

echo "Generated ${OUT_FILE}"
