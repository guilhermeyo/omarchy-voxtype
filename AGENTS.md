# Instructions for a coding agent installing this repo

You are reading this because someone handed you this repository and asked you to
set it up. This file is the script for that conversation. `CLAUDE.md` is a real file
that points here rather than a symlink to it, because `omarchy plugin validate`
rejects any symlink inside a plugin folder and this repo is checked out directly
as one.

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
| **A. Nowhere — just fix obvious typos** | pipeline `sed`, no LLM at all | nothing else, but see below |
| **B. On this machine** | ollama on localhost | a GPU with ~10 GB VRAM, or patience |
| **C. On another machine I have access to** | `LLM_URL` pointing at that host | the host's address, and that host reachable |
| **D. A paid API (OpenAI-compatible)** | `LLM_URL` + `LLM_KEY_FILE` | an API key |
| **E. Google Gemini** | the `gemini` stage | a Gemini API key |

**If they pick A, say the quiet part.** The `sed` stage has no rules by default,
so pipeline `sed` alone changes nothing at all — it is a working pipeline that
does no work. Start them off rather than leaving them puzzled:
`cp config/polish-sed.example.sed ~/.config/voxtype/polish-sed.sed`, then add one
`s/\bwrong\b/right/g` line per mistake they see their transcription make. A
punctuates nothing either — only an LLM stage inserts punctuation.

B, C, D and E all cost latency; A is instant and fully offline. C is the common
case for someone without a GPU who has a friend with one. Note for C and D: the
dictated text leaves this machine on every dictation. Say that out loud — do not
let them find out later.

**Q1b — Can this machine actually transcribe? Check, do not assume.**

Ask this BEFORE anything else if the hardware sounds old, and run the check
either way. It decides whether the rest of the install is even possible.

```bash
grep -o avx2 /proc/cpuinfo | head -1     # empty = no AVX2 = packaged binaries will not run
voxtype info variants                     # read "Recommended for this hardware"
```

voxtype ships AVX2 and AVX-512 builds; the `native` variants are not installed.
A pre-Haswell CPU (2013) has no AVX2 — a ThinkPad X220 and its generation cannot
run them, and their integrated GPUs are too old for the Vulkan path. This is not
a slow setup, it is one that does not start.

If the machine cannot transcribe locally, do NOT walk them through downloading
a Parakeet or Whisper model. Configure remote transcription instead:

```toml
[whisper]
mode = "remote"
remote_endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
remote_model = "whisper-large-v3"
```

with the key in `VOXTYPE_WHISPER_API_KEY` rather than in the config file. Any
OpenAI-compatible transcription endpoint works. Use `https` — voxtype warns that
plain HTTP sends the raw audio unencrypted. `--engine soniox` (`SONIOX_API_KEY`)
and `--engine cohere` are the two dedicated cloud engines if they prefer one.

Tell them plainly what this means: their voice is uploaded on every dictation,
and if they then pick a cloud polish stage in Q1, the text is uploaded again to
a second vendor.

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

## Check voxtype itself first

This repo post-processes voxtype's output; it cannot make voxtype work. Before
installing anything, confirm the thing underneath is alive:

```bash
voxtype setup check                    # model present, backend usable
systemctl --user is-active voxtype     # -> active
```

If either fails, stop: that is voxtype's setup, not this repo's. README.md steps
1, 2 and 4 walk through it, and the daemon's unit comes from
`voxtype setup systemd`, which nothing here creates.

## Then install

`./install --dry-run` first, show the user what it will do, then `./install`.
It is idempotent, backs up anything it would overwrite, and never touches
`shell.json` or any key file. Read `README.md` for what it deliberately leaves
for a human.

Note that `install` links the bar plugin unconditionally — it has no flag to skip
that step. On a machine with no Omarchy the symlink it creates is inert and
harmless; if the user would rather not have it, remove it afterwards with
`rm ~/.config/omarchy/plugins/local.voxtype`.

After it runs, write `~/.config/voxtype/llm.conf` from `config/llm.conf.example`
according to the Q1 answer, and `~/.config/voxtype/polish-mode` according to the
pipeline you agreed on.

**`LLM_MODEL` is the one key you must get right**, because getting it wrong fails
silently — the endpoint 404s, the stage counts as failed, and the dictation comes
back merely unpunctuated. It has to name a model the endpoint actually serves:

| Q1 | `LLM_MODEL` |
|---|---|
| B | build it first: `ollama pull qwen2.5:7b && ollama create vp-qwen7 -f config/vp-qwen.Modelfile`, then `vp-qwen7`. Or skip the build and point at `qwen2.5:7b` directly — `LLM_SEND_SYSTEM` defaults to 1, so a stock model works |
| C | whatever that host serves. Ask, or run `curl -s http://HOST:11434/api/tags \| jq -r '.models[].name'` |
| D | the vendor's model id |

The shipped `llm.conf.example` says `vp-qwen7`, which exists only on a machine
that ran the `ollama create` above. For C and D you must change it.

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
  the user's bar. If the plugin needs enabling, run `omarchy-shell shell rescanPlugins` FIRST and
  then `omarchy plugin enable local.voxtype`. The rescan is not optional:
  `enable` resolves the id against the running shell's registry, which was built
  at shell startup and has never seen the symlink you just created — without it
  you get `omarchy-plugin-enable: plugin 'local.voxtype' is not known`.
- Do not rewrite the Brazilian-Portuguese comments in the QML and in
  `bin/voxtype-punct`. They are the author's and they are load-bearing
  documentation of why each guard exists.
- If `~/.config/voxtype/config.toml` already exists, do not rewrite it. Add the
  `[output.post_process]` stanza and leave everything else alone.
