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

for key in GET_ON_LOAD_DATA_URL UPDATE_WORD_URL DELETE_WORD_URL CLOUDFLARE_ASSETS_URL; do
  if [[ -z "${!key:-}" ]]; then
    echo "error: ${key} is not set in .env" >&2
    exit 1
  fi
done

mkdir -p "${OUT_DIR}"
cat > "${OUT_FILE}" <<EOF
// Generated from .env — do not edit by hand.
// Regenerate via Scripts/generate-env.sh (Xcode build phase).

import Foundation

enum GeneratedEnv {
    static let getOnLoadDataURL = URL(string: "${GET_ON_LOAD_DATA_URL}")!
    static let updateWordURL = URL(string: "${UPDATE_WORD_URL}")!
    static let deleteWordURL = URL(string: "${DELETE_WORD_URL}")!
    static let cloudflareAssetsURL = URL(string: "${CLOUDFLARE_ASSETS_URL}")!
}
EOF

echo "Generated ${OUT_FILE}"
