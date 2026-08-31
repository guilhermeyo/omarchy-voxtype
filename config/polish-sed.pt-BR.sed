# polish-sed.pt-BR.sed — deterministic fixes for Brazilian Portuguese dictation.
#
# WHAT THIS IS
#   The `sed` stage of voxtype-punct runs an external sed script over the raw
#   transcript before any LLM sees it. This file is the rule set the author of
#   this project actually uses: accumulated repairs for what Parakeet mishears
#   when transcribing pt-BR, plus one English->Portuguese rewrite.
#
# THIS IS PORTUGUESE-SPECIFIC. DO NOT ENABLE IT FOR OTHER LANGUAGES.
#   `s/\band\b/e/g` rewrites the English conjunction "and" into the Portuguese
#   "e". The rule right above it protects a hardcoded list of English bigrams
#   ("drag and drop", "rock and roll", ...) by wrapping their "and" in a \x01
#   sentinel that a later rule unwraps — but that list is 21 entries long and
#   everything outside it is rewritten. English dictation WILL be corrupted.
#   `s/\bfor example\b/por exemplo/gI` translates outright.
#   If you dictate in anything but Brazilian Portuguese, start from
#   polish-sed.example.sed instead.
#
# HOW TO ENABLE
#   cp config/polish-sed.pt-BR.sed ~/.config/voxtype/polish-sed.sed
#   Or point at it without copying:  export VOX_SED_RULES=/path/to/this/file
#   No rules file at all = the sed stage is a no-op pass-through (the default).
#
# REQUIRES GNU sed. `\b` word boundaries, the `\x01` hex escape, the `I`
# case-insensitive flag on `s///` and `--sandbox` are GNU extensions; BSD/macOS
# sed will not work. Rules are applied with `sed --sandbox -E -f`, so use ERE
# syntax — and note that sandbox mode rejects the `e`, `r` and `w` commands, so
# a rules file cannot execute a shell command or write to disk.
#
# SAFETY
#   Every pattern is anchored with `\b` on both sides, so "momento", "andou",
#   "andando" and "sugetnai" are not touched.
#   A malformed rule here cannot lose your dictation: voxtype-punct checks
#   sed's exit status and returns the input unchanged if the script fails.

# ── ASR mishearings, pt-BR ───────────────────────────────────────────────────
s/\b[Ee]nto\b/então/g
s/\b[Mm]eba\b/ameba/g

# ── and -> e ────────────────────────────────────────────────────────────────
# Only the LOWERCASE form, and only outside known English bigrams, which are
# protected with a \x01 sentinel and restored two rules below. Capitalised
# "And" is left alone (English sentence openers).
s/\b(drag|rock|black|copy|cut|trial|back|plug|command|dungeons|research|drum|salt|read|search|supply|touch|hide|point|stop|pick) (and)\b/\1 \x01KEEP\2\x01/gI
s/\band\b/e/g
s/\x01KEEP([Aa][Nn][Dd])\x01/\1/g

# ── EN -> PT rewrite ────────────────────────────────────────────────────────
s/\b[Ff]or example\b/por exemplo/gI

# ── proper nouns this setup keeps hearing wrong ─────────────────────────────
s/\b[Pp]aracut\b/Parakeet/g
s/\b[Pp]arak[ií]t\b/Parakeet/g
s/\b[Gg]etn[aei]+\b/Gemini/g
# variant Parakeet produced on 2026-07-28
s/\b[Gg]eminai\b/Gemini/g
