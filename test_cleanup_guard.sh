#!/bin/bash
# Regression test for the post-process fail-safe: model chatter (refusals,
# answers, hallucinated content) must never replace the transcript.
# Incident 2026-07-09: llama3.2:3b refused a dictated sentence about sudo and
# the refusal text got pasted at the cursor instead of the user's words.
#
# Runs offline (no Ollama needed): tests the is_faithful_cleanup guard directly.

cd "$(dirname "$0")" || exit 1

# Extract the guard + preamble-strip functions from xhisper.sh
GUARD_SRC=$(sed -n '/^is_faithful_cleanup()/,/^}$/p' xhisper.sh)
if [ -z "$GUARD_SRC" ]; then
  echo "FAIL: is_faithful_cleanup() not found in xhisper.sh"
  exit 1
fi
eval "$GUARD_SRC"
STRIP_SRC=$(sed -n '/^strip_preamble()/,/^}$/p' xhisper.sh)
if [ -z "$STRIP_SRC" ]; then
  echo "FAIL: strip_preamble() not found in xhisper.sh"
  exit 1
fi
eval "$STRIP_SRC"

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

# Formatter-style restructuring (newlines, bullets, dropped command words)
# must still count as faithful
FMT_IN="and if I just say, new line, this is something else on the second line, and I'm just gonna list a few things, so the list is, important stuff, my phone, Pepsi Max, my backpack, that is all on the list"
FMT_OUT="And if I just say:
This is something else on the second line. I'm just gonna list a few things. The list is:
- important stuff
- my phone
- Pepsi Max
- my backpack
That is all on the list."
expect accept "formatter output accepted" "$FMT_IN" "$FMT_OUT"

# Incident 2 (2026-07-09): the formatter INVENTED list items the speaker
# never said ("- Windows - Python - JavaScript") and the guard passed it.
# The output may contain at most 2 words absent from the input.
INV_IN="XHesper, there's a lot of spelling mistakes here that it should simply just fix in the cleanup automatically. Like we want to keep a word count of all this and then clean up automatically. It should look for these types of things that are programs and system names and stuff like that and then fix them when I speak."
INV_OUT="$INV_IN

- Windows
- Python
- JavaScript"
expect reject "invented list items rejected" "$INV_IN" "$INV_OUT"

# Invention built from the speaker's OWN words (duplicated into fake list
# items) must also be rejected: counted as a multiset, not unique words
DUP_OUT="Hi, there's a lot of spelling mistakes here that it should simply just fix in the cleanup automatically. Like we want to keep a word count of all this and then clean up automatically. It should look for these types of things that are programs and system names and stuff like that and then fix them when I speak.

- Programs
- System names"
expect reject "duplicated-word list items rejected" "$INV_IN" "$DUP_OUT"

# Vocabulary spelling fixes introduce a couple of new words; still accepted
expect accept "vocab spelling fix accepted" \
  "I use Calistia with XHesper on Arch" \
  "I use caelestia with xhisper on Arch."

# Incident 3 (2026-07-09): Japanese dictation. No spaces means word-level
# tokens are blind; hallucinated sentences must burn per-character budget.
JA_IN="はじめまして、マークスです。"
JA_OUT="はじめまして、マークスです。

私は日本人ですが、現在はアメリカで生活しています。"
expect reject "japanese hallucination rejected" "$JA_IN" "$JA_OUT"

# Punctuation-only changes in Japanese stay accepted
expect accept "japanese punctuation fix accepted" \
  "はじめまして マークスです" \
  "はじめまして、マークスです。"

# strip_preamble: model-added header lines must go, dictated content must stay
check_strip() {
  local name="$1" input="$2" want="$3"
  local got
  got=$(strip_preamble "$input")
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name"
    printf '  want: [%q]\n  got:  [%q]\n' "$want" "$got"
    FAIL=$((FAIL + 1))
  fi
}

check_strip "known preamble stripped" \
  "Here is the formatted transcript:

Alright, so this is a test." \
  "Alright, so this is a test."

check_strip "dictated colon line kept" \
  "Here is my plan:
- first thing
- second thing" \
  "Here is my plan:
- first thing
- second thing"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
