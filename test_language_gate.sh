#!/bin/bash
# Tests for the language gate: the LLM formatter only runs for languages it
# actually speaks (post-process-languages allowlist, default "en").

cd "$(dirname "$0")" || exit 1

SRC=$(sed -n '/^post_process_language_ok()/,/^}$/p' xhisper.sh)
if [ -z "$SRC" ]; then
  echo "FAIL: post_process_language_ok() not found in xhisper.sh"
  exit 1
fi
eval "$SRC"

LANG_FILE=$(mktemp)
trap 'rm -f "$LANG_FILE"' EXIT
post_process_languages="en"

PASS=0
FAIL=0

check() {
  local name="$1" lang="$2" want="$3" got
  if [ "$lang" = "MISSING" ]; then
    rm -f "$LANG_FILE"
  else
    printf '%s' "$lang" > "$LANG_FILE"
  fi
  if post_process_language_ok; then got="allow"; else got="skip"; fi
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (wanted $want, got $got)"
    FAIL=$((FAIL + 1))
  fi
}

check "english allowed" "en" allow
check "japanese skipped" "ja" skip
check "danish skipped" "da" skip
check "no lang file falls back to allow" "MISSING" allow

post_process_languages="en,da"
check "allowlist is configurable" "da" allow

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
