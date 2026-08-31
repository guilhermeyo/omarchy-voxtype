# `config/` — what goes where

Nothing in this directory is read from the repo at runtime. `bin/voxtype-punct`
looks for everything under **`$XDG_CONFIG_HOME/voxtype`**, or
**`~/.config/voxtype`** when that variable is not set — the paths below assume
the latter, which is the usual case. voxtype itself reads `config.toml` from the
same directory. These files are the sources you copy from.

`config.toml.example` must be edited before it works, and `llm.conf.example`
must be edited if you point the `qwen` stage anywhere but a local ollama on this
machine. The rest are ready to use as-is. The table is the short version, the
sections below explain each one.

| File | Copy to | Status |
|---|---|---|
| `config.toml.example` | `~/.config/voxtype/config.toml` | **example — must be edited** |
| `llm.conf.example` | `~/.config/voxtype/llm.conf` | optional — where the `qwen` stage sends your text |
| `polish-prompt.txt` | `~/.config/voxtype/polish-prompt.txt` | ready to use, any language — sent by **both** LLM stages |
| `polish-prompt.pt-BR.txt` | `~/.config/voxtype/polish-prompt.txt` | optional, Brazilian Portuguese only |
| `polish-sed.example.sed` | `~/.config/voxtype/polish-sed.sed` | optional starting point |
| `polish-sed.pt-BR.sed` | `~/.config/voxtype/polish-sed.sed` | optional, **destroys English** |
| `vp-qwen.Modelfile` | not copied — fed to `ollama create` | optional — a local model with the prompt baked in |
| `systemd/gpu.conf` | `~/.config/systemd/user/voxtype.service.d/gpu.conf` | optional, NVIDIA only |
| `README.md` | not copied — this file | — |

That is every file in `config/`. If you add one, add a row.

> **`gemini.key` is not in this repo and never will be.** The `gemini` pipeline
> stage reads a Google Generative Language API key from
> `~/.config/voxtype/gemini.key`. Create it by hand:
>
> ```bash
> install -m 600 /dev/null ~/.config/voxtype/gemini.key
> printf '%s' 'YOUR_AI_STUDIO_KEY' > ~/.config/voxtype/gemini.key
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

## `llm.conf.example` — where the `qwen` stage sends your text

**Optional. Copy to `~/.config/voxtype/llm.conf`, then edit it.** Skip it
entirely if you run ollama on this machine and built `vp-qwen7` from
`vp-qwen.Modelfile` — the wrapper's own built-in defaults already point there.

The stage named `qwen` does not mean "ollama on this machine". It means *your*
LLM endpoint: this box, a machine on your LAN, the far end of a VPN, or a paid
API. This file is where that is declared.

**Why a file and not an environment variable.** `bin/voxtype-punct` is spawned
by the voxtype daemon under `systemd --user`, so an `export` in your shell never
reaches it. Environment variables (`VOX_LLM_URL`, `VOX_LLM_MODEL`, and the
legacy `OLLAMA_URL` / `OLLAMA_MODEL`) are useful only when you run the wrapper
by hand in a terminal to test something.

The file is **parsed**, never sourced — `KEY = value`, one per line, `#` starts
a comment, quotes around the value optional — so a config file can never become
a script that runs on every dictation. Only the keys below are read; anything
else is ignored. **There is no `~` expansion anywhere in it: write absolute
paths.**

| Key | Default | What it does |
|---|---|---|
| `LLM_URL` | `http://localhost:11434/api/generate` | The endpoint. Any HTTP URL the wrapper can reach. |
| `LLM_MODEL` | `vp-qwen7` | The model name as that endpoint knows it. |
| `LLM_API` | deduced from the URL path | `ollama` (`/api/generate`), `ollama-chat` (`/api/chat`) or `openai` (`/chat/completions`). Set it explicitly for a nonstandard path. |
| `LLM_KEY_FILE` | `~/.config/voxtype/llm.key` | File holding a bearer token, for an endpoint that wants one. Only the first line is used; no `Authorization` header is sent when the file is missing or empty. **Absolute path.** |
| `LLM_SEND_SYSTEM` | `1` | Send `polish-prompt.txt` as the system prompt on every request. See below. |
| `LLM_TIMEOUT` | `15` | Seconds for the whole response. |
| `LLM_CONNECT_TIMEOUT` | `1` on localhost, `5` elsewhere | Seconds for the TCP connect. Raise it for an endpoint at the end of a slow tunnel. |
| `GEMINI_MODEL` | `gemini-flash-latest` | The separate `gemini` stage's model id. That stage always talks to Google and has its own key file. |

**Leave `LLM_SEND_SYSTEM` on** unless your model already carries the punctuation
prompt. A stock model that receives no system prompt does not punctuate your
dictation — it *converses* with it, and its reply is what gets pasted into your
editor. The only reason to turn it off is a model built from
`vp-qwen.Modelfile`, which carries the same instructions internally.

Two timeouts, two failure shapes. `LLM_CONNECT_TIMEOUT` too low means the stage
fails on every dictation, silently, and you get unpunctuated text. Raising
`LLM_TIMEOUT` above ~20 without also raising `timeout_ms` under
`[output.post_process]` in `config.toml` means voxtype throws away the whole
post-process and types the raw transcript instead.

Pointing `LLM_URL` at another machine is a privacy decision of the same kind as
enabling `gemini`. "`qwen` is offline" is a statement about the shipped default,
not about whatever you put in this file.

## `polish-prompt.txt` — the LLM stages' instruction, shipped default

**Copy to `~/.config/voxtype/polish-prompt.txt`. Ready to use, no edits needed.**

This is the system prompt **both** LLM stages send. The cloud `gemini` stage
always sends it and refuses to run without it. The local `qwen` stage sends it
too, by default, because `LLM_SEND_SYSTEM` defaults to `1` — that is what lets
the stage point at a stock model instead of one with the prompt baked in.

Measured against the shipped wrapper, with a capture server standing in for the
endpoint: on defaults, the JSON `bin/voxtype-punct` POSTs to `LLM_URL` carries
the keys `model, options, prompt, stream, system`, and `system` is this file
verbatim (973 bytes). Set `LLM_SEND_SYSTEM = 0` in `llm.conf` and the same run
posts `model, options, prompt, stream` — no system prompt at all.

So editing this file changes what *both* stages do. The single exception is
`LLM_SEND_SYSTEM = 0`, which you set only for a model that already carries the
same instructions; then the `qwen` stage's instructions come from the model
itself — the `SYSTEM` block in [`vp-qwen.Modelfile`](vp-qwen.Modelfile) — and
you change them with `ollama create vp-qwen7 -f config/vp-qwen.Modelfile`.

> **The `gemini` stage is not in any default.** The installer writes `sed` into
> `polish-mode`, and the wrapper's failure-safe fallback — used when
> `polish-mode` is missing, empty or unparseable — is `sed+qwen`.
> `sed+qwen+?gemini` is the opt-in `auto` alias, and nothing selects it for you.
> So until you choose a pipeline containing `gemini`, the only stage that ever
> reads this file is `qwen`.

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

It occupies the same file as `polish-prompt.txt` and is therefore sent by the
same two stages, on the same terms: `gemini` always, `qwen` unless you set
`LLM_SEND_SYSTEM = 0`. If you have turned that off, the `qwen` stage's pt-BR
equivalent is editing the `SYSTEM` block in `vp-qwen.Modelfile` and re-running
`ollama create`.

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

**The `SYSTEM` block is what the `qwen` stage falls back on when the wrapper
sends no prompt of its own** — that is, when `LLM_SEND_SYSTEM = 0` is set in
`llm.conf`. That is the whole point of building this model: the instructions
travel with the model instead of being re-sent on every dictation. On the
default (`LLM_SEND_SYSTEM = 1`) the request carries `polish-prompt.txt` in its
own `system` field, and *that* is the instruction the request is answered
against. The shipped `SYSTEM` text is a copy of `polish-prompt.txt`, so the two
agree until you edit one; keep them in step if you care about both paths
behaving alike.

Each `ollama create vp-qwen7 -f config/vp-qwen.Modelfile` overwrites the
existing `vp-qwen7`, so re-running it is how you apply a `SYSTEM` edit.

The name `vp-qwen7` is `bin/voxtype-punct`'s built-in default for the `qwen`
stage. Change it, and the endpoint, in `~/.config/voxtype/llm.conf` (`LLM_MODEL`
and `LLM_URL` — copy `llm.conf.example`). **`OLLAMA_MODEL` and `OLLAMA_URL` are
not the way to do this.** They survive only as legacy *environment* fallbacks,
and environment variables cannot reach the wrapper in normal operation: it is
spawned by the voxtype daemon under `systemd --user`, so an `export` in your
shell changes nothing for a real dictation — and reports no error either.

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
