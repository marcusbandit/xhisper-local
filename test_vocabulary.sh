#!/bin/bash
# Tests for the vocabulary system: whisper-prompt list building and the
# deterministic alias rewrite (canonical = alias1, alias2).

cd "$(dirname "$0")" || exit 1

for fn in build_vocabulary apply_vocabulary_aliases; do
  SRC=$(sed -n "/^${fn}()/,/^}$/p" xhisper.sh)
  if [ -z "$SRC" ]; then
    echo "FAIL: ${fn}() not found in xhisper.sh"
    exit 1
  fi
  eval "$SRC"
done

# Fixture vocabulary
VOCAB_FILE=$(mktemp)
trap 'rm -f "$VOCAB_FILE"' EXIT
cat > "$VOCAB_FILE" <<'EOF'
# comment line

caelestia = Calistia, Celestia
xhisper = XHesper, X Hisper
Hyprland
Windows
EOF
build_vocabulary

PASS=0
FAIL=0

check() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    printf '  want: [%s]\n  got:  [%s]\n' "$want" "$got"
    FAIL=$((FAIL + 1))
  fi
}

check "whisper prompt list has canonicals only" \
  "$vocabulary" \
  "caelestia, xhisper, Hyprland, Windows"

check "alias rewritten" \
  "$(apply_vocabulary_aliases "the Calistia pill looks fine")" \
  "the caelestia pill looks fine"

check "alias at punctuation boundary" \
  "$(apply_vocabulary_aliases "XHesper, fix this")" \
  "xhisper, fix this"

check "multi-word alias" \
  "$(apply_vocabulary_aliases "I think X Hisper is broken")" \
  "I think xhisper is broken"

check "alias is case-insensitive" \
  "$(apply_vocabulary_aliases "calistia and CALISTIA")" \
  "caelestia and caelestia"

check "plain vocab words are never rewritten" \
  "$(apply_vocabulary_aliases "the windows in my house are open")" \
  "the windows in my house are open"

check "no partial-word matches" \
  "$(apply_vocabulary_aliases "the Calistian empire")" \
  "the Calistian empire"

# Alias-line terms get their canonical casing enforced (LLM re-casing fix)
check "canonical casing enforced for alias terms" \
  "$(apply_vocabulary_aliases "I think Caelestia and XHISPER are neat")" \
  "I think caelestia and xhisper are neat"

# Plain vocab lines never enforce casing (common-word safety)
check "plain terms keep the speaker's casing" \
  "$(apply_vocabulary_aliases "the windows are open")" \
  "the windows are open"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
