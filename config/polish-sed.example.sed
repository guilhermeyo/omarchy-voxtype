# polish-sed.example.sed — starter rules for the voxtype-punct `sed` stage.
#
# WHAT THIS IS
#   voxtype-punct's `sed` stage runs this file over the raw transcript, before
#   any LLM sees it. It is for deterministic repairs: words your speech-to-text
#   model reliably gets wrong, jargon it has never heard, names it mangles.
#   It does not punctuate — that is the LLM stages' job.
#
# HOW TO ENABLE
#   cp config/polish-sed.example.sed ~/.config/voxtype/polish-sed.sed
#   then edit that copy. Or point at a file anywhere:
#     export VOX_SED_RULES=/path/to/rules.sed
#   With no rules file the sed stage is a no-op pass-through — that is the
#   shipped default, and it is language-agnostic on purpose.
#
# FORMAT
#   A plain sed script, applied with `sed --sandbox -E -f` — extended regular
#   expressions, sandbox mode. One command per line. `#` starts a comment.
#   GNU sed is required: `\b`, `\x01`, the `I` flag and `--sandbox` are all GNU
#   extensions.
#
#   `--sandbox` is what keeps a rules file DATA instead of a program. It makes
#   GNU sed reject the `e`, `r` and `w` commands outright ("e/r/w commands
#   disabled in sandbox mode") and refuse to load the script. Without it,
#   `s/x/y/e` would run a shell command and `s/x/y/w somefile` would write your
#   dictation to disk — which matters because VOX_SED_RULES invites you to point
#   this stage at a rules file you did not write. A rejected script costs you
#   nothing: voxtype-punct sees the non-zero exit and returns the text unchanged.
#
# RULES OF THUMB
#   - Anchor everything with \b on both sides, or "and" will match inside
#     "andando" and "band".
#   - Prefer repairing NON-WORDS (things no language spells that way) over
#     rewriting real words. A rule that fires on a valid word will eventually
#     destroy a proper noun or a quotation.
#   - Never translate here. The LLM stages are instructed to answer in the
#     input's own language; a sed rule that translates silently contradicts
#     them, with no way for you to notice.
#   - Test a rule before trusting it, with the same flags the stage uses:
#       printf '%s' "your test sentence" | sed --sandbox -E -f ~/.config/voxtype/polish-sed.sed
#   - A malformed script cannot cost you a dictation: voxtype-punct checks
#     sed's exit status and returns the text unchanged if this file fails.
#     Run with VOX_TRACE=1 to see which path was taken.

# ── the shape of a fix ──────────────────────────────────────────────────────
# Uncomment and adapt. Left side: what the model hears. Right side: what you
# actually said.
#
# s/\bwrong\b/right/g
#
# Real examples of the useful kind — a product name your model has never seen:
# s/\b[Kk]ubernetties\b/Kubernetes/g
# s/\b[Pp]ost gres\b/PostgreSQL/gI

# ── safe, language-neutral cleanup ──────────────────────────────────────────
# Collapse runs of spaces and tabs into one space.
s/[[:blank:]]{2,}/ /g

# Drop spaces before , . ; : ! ? — most languages that use these punctuation
# marks close them tight. Remove this rule if you dictate in French, which
# spaces ; : ! ? deliberately.
s/[[:blank:]]+([,.;:!?])/\1/g

# Trim trailing whitespace at end of line.
s/[[:blank:]]+$//
