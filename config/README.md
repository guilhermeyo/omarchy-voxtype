# `config/` — what goes where

Nothing in this directory is read from the repo at runtime. `bin/voxtype-punct`
looks for everything under **`~/.config/voxtype/`**, and voxtype itself reads
`~/.config/voxtype/config.toml`. These files are the sources you copy from.

Two of them are *examples* you must edit before they work; the rest are ready to
use as-is. The table is the short version, the sections below explain each one.

| File | Copy to | Status |
|---|---|---|
| `config.toml.example` | `~/.config/voxtype/config.toml` | **example — must be edited** |
| `polish-prompt.txt` | `~/.config/voxtype/polish-prompt.txt` | ready to use, any language — **`gemini` stage only** |
| `polish-prompt.pt-BR.txt` | `~/.config/voxtype/polish-prompt.txt` | optional, Brazilian Portuguese only |
| `polish-sed.example.sed` | `~/.config/voxtype/polish-sed.sed` | optional starting point |
| `polish-sed.pt-BR.sed` | `~/.config/voxtype/polish-sed.sed` | optional, **destroys English** |
| `vp-qwen.Modelfile` | not copied — fed to `ollama create` | ready to use — the `qwen` stage's instructions |
| `systemd/gpu.conf` | `~/.config/systemd/user/voxtype.service.d/gpu.conf` | optional, NVIDIA only |
| `README.md` | not copied — this file | — |

That is every file in `config/`. If you add one, add a row.

> **`gemini.key` is not in this repo and never will be.** The `gemini` pipeline
> stage reads a Google Generative Language API key from
> `~/.config/voxtype/gemini.key`. Create it by hand:
>
> ```bash
> install -m 600 /dev/null ~/.config/voxtype/gemini.key
> printf '%s' 'YOUR_API_KEY' > ~/.config/voxtype/gemini.key
> ```
>
> Get the key from Google AI Studio. Without this file the `gemini` stage is
> skipped; the rest of the pipeline still runs. Mode `0600` matters — the file
> is a credential. It is listed in the repo's `.gitignore` so that a stray
> `git add -A` after an install cycle cannot commit it.

---

## `config.toml.example` — voxtype's own config

**Copy to `~/.config/voxtype/config.toml`, then edit two things at minimum.**

1. **`[output.post_process] command`** is the line that wires this project in.
   It ships as `/home/YOUR_USERNAME/.local/bin/voxtype-punct`. Replace
   `YOUR_USERNAME` with the output of `whoami`. voxtype does **not** expand `~`
   or `$HOME` here, so the path must be absolute. If the path is wrong, voxtype
   fails **silently**: it falls back to the raw transcript, with no error and no
   notification. A dictation that suddenly stops being punctuated is almost
   always this line.

2. **`language`** ships as `"auto"`. Set it to your own language code if your
   speech-to-text engine does better with an explicit one.

The file is otherwise the author's live config, measured on an NVIDIA RTX 3090
running the CUDA build of voxtype. Several values are tuned to that machine and
should be reviewed before you trust them elsewhere — `timeout_ms`, the engine and
model names, `flash_attention`, `gpu_isolation` and the clipboard restore delay.
The comments in the file itself say which is which.

## `polish-prompt.txt` — the cloud stage's instruction, shipped default

**Copy to `~/.config/voxtype/polish-prompt.txt`. Ready to use, no edits needed.**

This is the system prompt the **cloud `gemini` stage** sends — that stage and no
other. The local `qwen` stage sends **no system prompt at all**: `try_local()` in
`bin/voxtype-punct` posts `{model, prompt, stream}` and nothing else, because the
local model's instructions are baked into `vp-qwen7` by
[`vp-qwen.Modelfile`](vp-qwen.Modelfile).

That distinction bites in one specific way. On the default `sed+qwen+?gemini`
pipeline the `gemini` stage only runs when `qwen` goes quiet, so editing this
file can look like it does nothing — because most of the time nothing reads it.
**To change what the local model does, edit the `SYSTEM` block in
`vp-qwen.Modelfile` and re-run `ollama create vp-qwen7 -f
config/vp-qwen.Modelfile`.**

The prompt is deliberately language-agnostic — it tells the model to punctuate
and fix obvious transcription errors, to answer in **the input's own language**,
and never to translate. Dictate in any language and it behaves.

If you tune it, keep the "reply with the final text and nothing else" line. The
stage takes the model's whole answer as the text to paste, so a model that adds
"Here is the corrected text:" will paste that too. The same applies to the
`SYSTEM` block in the Modelfile.

## `polish-prompt.pt-BR.txt` — worked example, Brazilian Portuguese

**Optional. Copy over `~/.config/voxtype/polish-prompt.txt` to use it.**

The author's own tuned prompt, written in Portuguese, naming Portuguese-specific
repairs ("Ento"→"Então", "nao"→"não") and a list of pt-BR colloquial forms the
model must not "correct" away (pra, tô, cê, a gente, né). It replaces the default
prompt rather than adding to it.

Like `polish-prompt.txt`, it is read by the `gemini` stage only. The local
`qwen` stage has no prompt file — its pt-BR equivalent is editing the `SYSTEM`
block in `vp-qwen.Modelfile` and re-running `ollama create`.

It is kept in the repo as the worked example of what a per-language prompt looks
like. If you dictate in another language, write your own the same way — start
from `polish-prompt.txt` and add the mishearings and colloquialisms your own
engine gets wrong.

## `polish-sed.example.sed` — deterministic repairs, neutral starting point

**Optional. Copy to `~/.config/voxtype/polish-sed.sed`.**

The `sed` stage runs an external sed script over the raw transcript before any
LLM sees it. **With no rules file the stage is a no-op pass-through — that is the
shipped default**, and it is language-agnostic on purpose.

This file is the safe starting point: a commented explanation of the format, the
rules of thumb (anchor with `\b`, repair non-words rather than real words, never
translate), and three genuinely neutral cleanups — collapsing runs of blanks,
removing spaces before `,.;:!?`, trimming trailing whitespace. Everything else is
commented out for you to adapt.

`VOX_SED_RULES=/path/to/rules.sed` points the stage at a file anywhere, which is
the easy way to test a rule set without touching `~/.config`.

The stage runs `sed --sandbox -E -f`. Sandbox mode rejects GNU sed's `e`, `r`
and `w` commands, so a rules file is data and never a program — it cannot run a
shell command or write your dictation to disk. That guard is what makes
`VOX_SED_RULES` safe to point at a file you did not write yourself.

Requires **GNU sed** (`\b`, `\x01`, the `I` flag and `--sandbox` are GNU
extensions; BSD and macOS sed will not run these scripts).

## `polish-sed.pt-BR.sed` — the author's rules. **Portuguese only.**

**Optional. Copy to `~/.config/voxtype/polish-sed.sed` only if you dictate in
Brazilian Portuguese.**

> ### Warning: this file corrupts English dictation.
>
> It contains `s/\band\b/e/g` — the English conjunction "and" rewritten to the
> Portuguese "e". A hardcoded list of 21 English bigrams ("drag and drop", "rock
> and roll", …) is protected; **everything outside that list is rewritten**.
> "bread and milk" becomes "bread e milk". It also contains
> `s/\b[Ff]or example\b/por exemplo/gI`, which translates outright, and
> `s/\b[Mm]eba\b/ameba/g`, which will lowercase and replace a capitalised proper
> noun spelled that way. It is not only English that loses: Danish and
> Norwegian *and* ("duck") and Turkish *and* ("oath") are ordinary words that
> this rule silently turns into the Portuguese "e", and any language in which
> the token "ento" occurs is hit by the rule above it.
>
> The corruption is silent. There is no error, no notification, and nothing in
> the history log flags it — you find out by rereading what you pasted.

Everything in it is genuinely useful for the setup it came from: accumulated
repairs for what Parakeet mishears when transcribing pt-BR, plus the proper nouns
this project keeps needing ("Paracut" → "Parakeet", "getnae" → "Gemini"). It is
shipped as an opt-in example precisely so that it is never anyone's default.

## `vp-qwen.Modelfile` — the local ollama model

**Not copied anywhere. Fed to `ollama create`:**

```bash
ollama create vp-qwen7 -f config/vp-qwen.Modelfile
ollama list        # vp-qwen7 should appear
```

`FROM qwen2.5:7b`, the language-agnostic prompt baked in as `SYSTEM`, and
`temperature 0.1` so the model repairs instead of rewriting.

**The `SYSTEM` block is the `qwen` stage's only source of instructions.** The
wrapper sends the local model just the text, so `polish-prompt.txt` has no
effect on it whatsoever. Every change to the local model's behaviour — a
different language, extra repairs, a house style — is an edit here followed by
another `ollama create vp-qwen7 -f config/vp-qwen.Modelfile`, which overwrites
the existing `vp-qwen7`. The shipped `SYSTEM` text is a copy of
`polish-prompt.txt`; keep them in step if you edit one and care about the two
stages behaving alike.

The name `vp-qwen7` is what `bin/voxtype-punct`'s `qwen` stage asks for by
default; override it with `OLLAMA_MODEL=<name>`, and the endpoint with
`OLLAMA_URL=http://<host>:11434/api/generate` if ollama runs on another machine.

Pulling `qwen2.5:7b` downloads several gigabytes on first `create`. A smaller
base works — edit the `FROM` line — at some cost in punctuation quality.

## `systemd/gpu.conf` — optional, NVIDIA only

**Copy to `~/.config/systemd/user/voxtype.service.d/gpu.conf`, then reload:**

```bash
mkdir -p ~/.config/systemd/user/voxtype.service.d
cp config/systemd/gpu.conf ~/.config/systemd/user/voxtype.service.d/gpu.conf
systemctl --user daemon-reload
systemctl --user restart voxtype
```

Two lines that pin voxtype's Vulkan backend to the NVIDIA device
(`VOXTYPE_VULKAN_DEVICE=nvidia`) on a machine with more than one GPU. **Skip this
file entirely on AMD, Intel or single-GPU systems** — it names a device that does
not exist there.
