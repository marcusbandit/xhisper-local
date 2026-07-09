#!/bin/bash
# Tests for the deterministic voice-command pass (apply_voice_commands).
# This runs on the final text AFTER the LLM formatter (or its guard fallback),
# so spoken commands work even when the model output was rejected.

cd "$(dirname "$0")" || exit 1

FUNC_SRC=$(sed -n '/^apply_voice_commands()/,/^}$/p' xhisper.sh)
if [ -z "$FUNC_SRC" ]; then
  echo "FAIL: apply_voice_commands() not found in xhisper.sh"
  exit 1
fi
eval "$FUNC_SRC"

PASS=0
FAIL=0

check() {
  local name="$1" input="$2" want="$3"
  local got
  got=$(apply_voice_commands "$input")
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    printf '  want: [%q]\n  got:  [%q]\n' "$want" "$got"
    FAIL=$((FAIL + 1))
  fi
}

# The spoken command from the user's test dictation
check "new line between commas" \
  "and if I just say, new line, this is something else on the second line" \
  "and if I just say,
this is something else on the second line"

# Capitalised variant after a period
check "new line after period" \
  "That is done. New line, next thing." \
  "That is done.
next thing."

check "new paragraph" \
  "first topic ends here, new paragraph, second topic starts" \
  "first topic ends here,

second topic starts"

check "bullet points" \
  "the list is, bullet point, my phone, bullet point, Pepsi Max" \
  "the list is,
- my phone,
- Pepsi Max"

# Content that merely mentions a new line must NOT be converted
check "no false positive on content" \
  "we need to add a new line to the config file" \
  "we need to add a new line to the config file"

check "trailing command" \
  "that is the end, new line" \
  "that is the end,"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
