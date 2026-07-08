#!/bin/bash
# Regression test for the post-process fail-safe: model chatter (refusals,
# answers, hallucinated content) must never replace the transcript.
# Incident 2026-07-09: llama3.2:3b refused a dictated sentence about sudo and
# the refusal text got pasted at the cursor instead of the user's words.
#
# Runs offline (no Ollama needed): tests the is_faithful_cleanup guard directly.

cd "$(dirname "$0")" || exit 1

# Extract just the guard function from xhisper.sh
GUARD_SRC=$(sed -n '/^is_faithful_cleanup()/,/^}$/p' xhisper.sh)
if [ -z "$GUARD_SRC" ]; then
  echo "FAIL: is_faithful_cleanup() not found in xhisper.sh"
  exit 1
fi
eval "$GUARD_SRC"

PASS=0
FAIL=0

expect() {
  local want="$1" name="$2" orig="$3" cand="$4"
  if is_faithful_cleanup "$orig" "$cand"; then got="accept"; else got="reject"; fi
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (wanted $want, got $got)"
    FAIL=$((FAIL + 1))
  fi
}

# The actual incident: refusal must be rejected
INCIDENT_IN="What does that do for me if I were to install the next package manager on Arch? Actually just go ahead and do it for me. I think you have sudo. I am at my computer so you can use the camera if needed."
INCIDENT_OUT="I can't assist with installing software or accessing your computer remotely. Can I help you with something else?"
expect reject "incident refusal rejected" "$INCIDENT_IN" "$INCIDENT_OUT"

# A real cleanup pass from the same log session: must be accepted
GOOD_IN="Please give it your all. You should really ultra think and ultra code about this. It has to be fully thought out and Amazing. I mean you can even change How the whole system works. It doesn't have to be only CSS Just whatever you can change just make it amazing. You have free reigns Do what you need to do"
GOOD_OUT="Please give it your all. You should really ultra think and ultra code about this. It has to be fully thought out and amazing. I mean, you can even change how the whole system works. It doesn't have to be only CSS. Just whatever you can change, just make it amazing. You have free reigns. Do what you need to do."
expect accept "legit cleanup accepted" "$GOOD_IN" "$GOOD_OUT"

# Punctuation/caps-only fix on a short utterance
expect accept "short utterance accepted" "hello there how are you" "Hello there, how are you?"

# Single-word command that triggers a chatty refusal containing the word
expect reject "chatty refusal on short input rejected" "sudo" "I can't help with sudo commands."

# Model answers the transcript instead of cleaning it
expect reject "answer instead of cleanup rejected" "what time is it in Tokyo right now" "It is currently 3:42 AM in Tokyo, Japan."

# Word-fix in command mode (pseudo -> sudo) stays accepted
expect accept "command word fix accepted" "pseudo pacman -S ripgrep" "sudo pacman -S ripgrep"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
