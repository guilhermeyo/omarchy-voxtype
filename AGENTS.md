# Instructions for a coding agent installing this repo

You are reading this because someone handed you this repository and asked you to
set it up. This file is the script for that conversation. `CLAUDE.md` is a
symlink to this file.

This repo adds two things to **voxtype** (a third-party push-to-talk dictation
tool, https://voxtype.io — it is NOT part of this repo and must be installed
separately):

1. `bin/voxtype-punct` — a post-processor that punctuates the raw transcript,
   through an ordered pipeline of stages (`sed`, `qwen`, `gemini`).
2. An Omarchy/Quickshell bar plugin that shows and edits that pipeline, plus a
   dictation-history window.

The bar plugin only makes sense on Omarchy. The post-processor works on any
Linux box running voxtype, with no bar at all.

## Do not guess. Ask these questions first.

Ask them in the user's own language. Ask them one at a time if the user seems
unsure, all at once if they seem to know what they want. Do NOT start editing
files before you have answers to Q1, Q2 and Q3.

**Q1 — Where should the punctuation model run?**

| Answer | What you configure | What they need |
|---|---|---|
| **A. Nowhere — just fix obvious typos** | pipeline `sed`, no LLM at all | nothing else |
| **B. On this machine** | ollama on localhost | a GPU with ~10 GB VRAM, or patience |
| **C. On another machine I have access to** | `LLM_URL` pointing at that host | the host's address, and that host reachable |
| **D. A paid API (OpenAI-compatible)** | `LLM_URL` + `LLM_KEY_FILE` | an API key |
| **E. Google Gemini** | the `gemini` stage | a Gemini API key |

B, C, D and E all cost latency; A is instant and fully offline. C is the common
case for someone without a GPU who has a friend with one. Note for C and D: the
dictated text leaves this machine on every dictation. Say that out loud — do not
let them find out later.

**Q2 — What language will they dictate in?**

This matters in three separate places and getting it wrong degrades the output
silently:

- `language` in `~/.config/voxtype/config.toml` — the speech recognition. `auto`
  works; pinning it to their language is more accurate.
- `~/.config/voxtype/polish-prompt.txt` — the punctuation prompt. The shipped
  default is language-agnostic and tells the model to answer in whatever language
  it was given. `config/polish-prompt.pt-BR.txt` is a tuned Brazilian-Portuguese
  example; a tuned prompt beats the generic one.
- `~/.config/voxtype/polish-sed.sed` — deterministic find-and-replace rules.
  **There is no default and that is deliberate.** `config/polish-sed.pt-BR.sed`
  rewrites the English word "and" to "e". Never install it for someone who is
  not dictating Portuguese.

**Q3 — Are they on Omarchy, and do they want the bar plugin?**

Check: `command -v omarchy` and `command -v omarchy-shell`. If those are missing,
install only the post-processor and say the bar plugin is not applicable. Do not
try to make the QML work outside Omarchy.

**Q4 — only if they answered C, D or E: where should the key live?**

There is exactly one right answer and you should state it rather than ask:

- Remote or paid endpoint → `~/.config/voxtype/llm.key`
- Google Gemini → `~/.config/voxtype/gemini.key`

Both are plain files containing only the key, mode `600`, and both are outside
this repo on purpose. `.gitignore` blocks `*.key` so a key can never be committed
by accident. Create one with:

```bash
install -m 600 /dev/null ~/.config/voxtype/llm.key
$EDITOR ~/.config/voxtype/llm.key      # paste the key, nothing else, no quotes
```

**Never** put a key in `llm.conf`, in `config.toml`, in a shell rc file, or in
any file inside this repo. Never echo a key into your own transcript, and never
read one back to confirm it — check it with `test -s`, not by printing it.

## Then install

`./install --dry-run` first, show the user what it will do, then `./install`.
It is idempotent, backs up anything it would overwrite, and never touches
`shell.json` or any key file. Read `README.md` for what it deliberately leaves
for a human.

After it runs, write `~/.config/voxtype/llm.conf` from `config/llm.conf.example`
according to the Q1 answer, and `~/.config/voxtype/polish-mode` according to the
pipeline you agreed on:

| Q1 answer | polish-mode |
|---|---|
| A | `sed` |
| B, C, D | `sed+qwen` |
| E | `sed+gemini` |
| C or D, with Gemini as a backup | `sed+qwen+?gemini` |

## Then verify, and show them the output

```bash
printf 'this is a test of the dictation pipeline' \
  | VOX_TRACE=1 VOX_NO_HISTORY=1 ~/.local/bin/voxtype-punct
```

The trace goes to stderr and is in Brazilian Portuguese (`ok qwen` = the stage
worked; `FAIL qwen (text intacto)` = it failed and the text was preserved). With
pipeline `sed` and no rules file, unchanged output is SUCCESS, not failure.

Then restart the daemon — `systemctl --user restart voxtype` — and have them
actually dictate something. Nothing is verified until text lands in a real window.

## Tell them these two things before you finish

1. **Every dictation is logged in plaintext** to
   `~/.local/state/voxtype/history.jsonl`, by this wrapper, mode 600. That is how
   the history window works. `VOX_NO_HISTORY=1` disables it. They should know
   this file exists before they dictate a password into it.
2. If they chose C, D or E, their dictation is sent to that endpoint on every
   single dictation. The bar icon shows which stage is active precisely so this
   is visible at a glance.

## Rules for you, the agent

- Do not edit anything under `~/.config/omarchy/` other than creating the plugin
  symlink. `shell.json` in particular is Omarchy's own file and a bad edit breaks
  the user's bar. If the plugin needs enabling, use `omarchy plugin enable`.
- Do not rewrite the Brazilian-Portuguese comments in the QML and in
  `bin/voxtype-punct`. They are the author's and they are load-bearing
  documentation of why each guard exists.
- If `~/.config/voxtype/config.toml` already exists, do not rewrite it. Add the
  `[output.post_process]` stanza and leave everything else alone.
