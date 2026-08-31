# omarchy-voxtype

An Omarchy bar plugin plus the post-processing pipeline that turns raw
[voxtype](https://voxtype.io) dictation into text you can actually paste into a
commit message: punctuation, capitalisation and accents, without rewriting what
you said. voxtype itself is third-party software and is **not** vendored here —
you install it from your distro's repos, and this project bolts onto its
`[output.post_process]` hook and its Wayland output path.

Built and used daily on Arch + Omarchy 4.0.0.alpha (Hyprland, Quickshell 0.3.1),
NVIDIA RTX 3090, Parakeet on CUDA. Everything else is documented as "should
work" and marked where it was not tested.

---

## Start here

If you have a coding agent (Claude Code, or anything that reads `AGENTS.md`),
the fastest path is to let it do the whole thing. Clone the repo and point the
agent at it:

```bash
git clone https://github.com/guilhermeyo/omarchy-voxtype.git
cd omarchy-voxtype
claude "read AGENTS.md and set this up for me"
```

`AGENTS.md` is written for exactly that: the agent asks you where the language
model should run, what language you dictate in, whether you are on Omarchy, and
where your key goes — then installs and verifies it. You do not have to read the
rest of this document.

This is a private repository. If `git clone` asks for credentials, you have not
been given access to it yet — ask the owner to add you as a collaborator.

Prefer to do it yourself? `./install --dry-run` shows you every change first,
then `./install` makes them. Or read [Install from scratch](#install-from-scratch)
and do it by hand. Every path ends in the same place.

## Which setup do you want?

This is the one decision that shapes everything else: **where the punctuation
model runs.** Answer this before you install anything.

| | Setup | You need | Latency | Your text leaves the machine |
|---|---|---|---|---|
| **A** | **No model.** Deterministic find-and-replace only. | nothing | none | no |
| **B** | **A model on this machine**, via ollama. | a GPU with ~10 GB VRAM | ~0.3 s | no |
| **C** | **A model on another machine** you can reach — a friend's box, your own server, something at the end of a VPN. | that host's address | ~0.3 s + network | **yes, to that host** |
| **D** | **A paid API** that speaks the OpenAI format. | an API key | ~1–3 s | **yes, to that vendor** |
| **E** | **Google Gemini.** | a Gemini API key | ~2–5 s | **yes, to Google** |

**C is the option most people want.** You do not need a GPU, you do not need
ollama installed, and you do not need to build a custom model — the wrapper
sends the punctuation prompt with every request, so any stock model works. One
file is the entire configuration:

```ini
# ~/.config/voxtype/llm.conf
LLM_URL   = http://192.168.1.50:11434/api/generate   # the machine with the GPU
LLM_MODEL = qwen2.5:7b
```

On the machine that *serves* the model, ollama has to listen on more than
loopback: set `OLLAMA_HOST=0.0.0.0:11434` in its systemd unit. Plain ollama has
no authentication, so only do that on a network you trust or behind a VPN.

They combine, too. `sed+qwen+?gemini` runs your own endpoint and falls back to
Google only when yours does not answer — the `?` means "only if the step above
failed". See [The pipeline spec](#the-pipeline-spec).

Full annotated options: [`config/llm.conf.example`](config/llm.conf.example).

## Where your key goes

Two files, both outside this repo, both mode `600`, both created by you:

| Setup | File | What it holds |
|---|---|---|
| D — paid OpenAI-compatible API | `~/.config/voxtype/llm.key` | the bearer token, alone on one line |
| E — Google Gemini | `~/.config/voxtype/gemini.key` | the API key, alone on one line |

A and B need no key at all. C needs one only if the endpoint you are pointing at
asks for one; a plain ollama on your LAN does not.

```bash
install -m 600 /dev/null ~/.config/voxtype/llm.key
$EDITOR ~/.config/voxtype/llm.key     # paste the key. Nothing else. No quotes,
                                      # no KEY= prefix, no trailing spaces.
```

The wrapper reads only the first line, so a stray newline is harmless. It sends
the key in an HTTP header fed to `curl` through a pipe — never on the command
line, because `/proc/<pid>/cmdline` is readable by every other process on the
machine.

**A key never belongs anywhere else.** Not in `llm.conf`, not in `config.toml`,
not in a shell rc file, not in this repository. `.gitignore` blocks `*.key` so a
key cannot be committed by accident, but that is a safety net, not a plan.

To get a key: Gemini keys come from Google AI Studio
(https://aistudio.google.com/apikey). OpenAI-compatible keys come from whichever
vendor you are using.

To rotate one: issue the new key, overwrite the file, then revoke the old one at
the vendor. There is nothing to restart — the wrapper reads the file on every
dictation, so the next thing you say already uses the new key.

## What you get

- **Switch the polish pipeline from the bar.** One icon that tells you at a
  glance whether your text is being polished locally, in the cloud, or not at
  all — click it for a native panel where you reorder stages, add and remove
  them, and mark a stage as a fallback.
- **Dictation history on `SUPER + SHIFT + V`.** A centred, searchable window
  with every dictation the wrapper has seen: what the ASR heard, what actually
  got pasted, `Enter` to copy. Stock voxtype has no such thing.
- **Punctuation that does not rewrite what you said.** The shipped prompt tells
  the model to punctuate, fix obvious transcription errors, and change nothing
  else — same language in, same language out, never translate. A measured
  length floor rejects an LLM that "helpfully" summarises your dictation instead
  of punctuating it.

---

## Architecture

```
   F9 (hold)                    ┌──────────────────────────────┐
   SUPER+CTRL+X  ──────────────►│  voxtype daemon (systemd)    │
   (Omarchy ships these)        │  ~/.config/voxtype/          │
                                │        config.toml           │
                                └───────────────┬──────────────┘
                                                │ 16 kHz mono audio
                                                ▼
                                ┌──────────────────────────────┐
                                │  Parakeet (ONNX / CUDA)      │
                                │  parakeet-tdt-0.6b-v3        │
                                └───────────────┬──────────────┘
                                                │ raw transcript, no punctuation
                                                ▼
     ┌────────────────────────────────────────────────────────────────────┐
     │  [output.post_process] command = ~/.local/bin/voxtype-punct        │
     │  stdin ──►  text  ──►  stdout          timeout_ms = 35000          │
     │                                                                    │
     │    spec: sed  →  qwen  ⇢  ?gemini  →  sed     (left to right)      │
     │           │        │         │                                     │
     │           │        │         └── HTTPS ──► generativelanguage      │
     │           │        │                       .googleapis.com  ☁      │
     │           │        └── HTTP ──► the endpoint in llm.conf,          │
     │           │                     ollama :11434 by default (local)   │
     │           └── sed --sandbox -E -f  <config>/polish-sed.sed (local) │
     └───────────┬──────────────────────────────────────────┬─────────────┘
                 │ polished text                            │ append, always
                 ▼                                          ▼
        wl-copy → clipboard                    ~/.local/state/voxtype/
                 │                                   history.jsonl  (0600)
                 │ wtype "shift+insert"                     │
                 ▼                                          │
        ┌────────────────┐                                  │ read + watch
        │  focused app   │                                  │
        └────────────────┘                                  │
                                                            │
   ┌────────────────────────────────────────────────────────┴─────────────┐
   │  bar plugin  local.voxtype   (Quickshell, inside omarchy-shell)      │
   │    bar icon + pipeline panel  ── read/write ──►  polish-mode         │
   │    history window (SUPER+SHIFT+V) ── read only ──►  history.jsonl    │
   └──────────────────────────────────────────────────────────────────────┘
```

### Who owns which file

`<config>` below is `$XDG_CONFIG_HOME/voxtype` when that variable is set, and
`~/.config/voxtype` otherwise. **`bin/voxtype-punct` and `./install` both
resolve it that way; the QML side does not** — `Service.qml` and `History.qml`
hardcode `$HOME/.config` and `$HOME/.local/state`. If you have moved
`XDG_CONFIG_HOME`, point the widget at the right file with the `modePath`
setting in `shell.json` (see Troubleshooting).

| File | Written by | Read by |
|---|---|---|
| `<config>/config.toml` | you, by hand (or `./install`) | voxtype daemon |
| `<config>/polish-mode` | the bar plugin (atomic writes), or `echo` | `voxtype-punct`, and the bar plugin watches it |
| `<config>/polish-sed.sed` | you (copy one of the examples) | `voxtype-punct`, `sed` stage only |
| `<config>/polish-prompt.txt` | you (copy `config/polish-prompt.txt`) | `voxtype-punct` — **both** the `qwen` and the `gemini` stage |
| `<config>/llm.conf` | you (copy `config/llm.conf.example`) | `voxtype-punct`, `qwen` stage only — where that stage sends your text |
| `<config>/llm.key` | you, chmod 600 | `voxtype-punct` — only if your `qwen` endpoint wants a bearer token |
| `<config>/gemini.key` | you, chmod 600 | `voxtype-punct`, `gemini` stage only |
| `~/.local/state/voxtype/history.jsonl` | `voxtype-punct`, every dictation | the history window |
| `~/.config/omarchy/shell.json` | `omarchy plugin enable`, or you | omarchy-shell, to decide the plugin is enabled |
| the `vp-qwen7` ollama model | `ollama create` | `voxtype-punct`, `qwen` stage only |

Two things that are **not** in that table because they surprise people:

- **The `qwen` stage sends `polish-prompt.txt` as its system prompt**, unless
  you set `LLM_SEND_SYSTEM = 0` in `llm.conf`. That is what lets the stage point
  at a stock model instead of a purpose-built one. Measured here, dictating
  English at a `vp-qwen7` whose baked-in `SYSTEM` block is Portuguese:

  ```
  with polish-prompt.txt   "hello world this is a test" -> "Hello, world. This is a test."
  LLM_SEND_SYSTEM = 0      "hello world this is a test" -> "Olá, mundo, isso é um teste."
  ```

  The second line is the model's own prompt taking over. `config/vp-qwen.Modelfile`
  in this repo ships a language-agnostic `SYSTEM`; if you already had a
  `vp-qwen7` built from an older, language-specific Modelfile, re-run
  `ollama create` over it.
- **The push-to-talk key is not in this repo and not in your `bindings.lua`.**
  Omarchy ships it at `~/.local/share/omarchy/default/hypr/bindings/voxtype.lua`,
  gated on `voxtype` being on `PATH`. You get `F9` (hold) and `SUPER+CTRL+X`
  for free. Only `SUPER+SHIFT+V` for the history window is yours to add.

---

## Requirements

Nothing here is checked by the plugin at runtime. A missing item shows up as
tofu boxes, a dead widget, or a silently unpolished dictation — never as an
error message. `./install` reports on most of them; this list is the whole set.

### Hard runtime dependencies

| What | Why | Check |
|---|---|---|
| `voxtype` | the thing being wrapped | `command -v voxtype` |
| `jq` | builds every LLM request body and every history line | `command -v jq` |
| `curl` ≥ 7.55 | both LLM stages; `-H @file` (which keeps your API key off the command line) needs 7.55+ | `curl --version \| head -1` |
| **GNU** sed | the `sed` stage uses `--sandbox`, `\b`, `\x01` and the `I` flag, all GNU extensions. BSD/macOS sed will not run these scripts | `sed --version \| head -1` |
| `wl-clipboard` (`wl-copy`) | the history window copies through `wl-copy` (`History.qml:74`), and voxtype's `mode = "paste"` puts the text on the clipboard | `command -v wl-copy` |
| `wtype` | how voxtype presses `shift+insert` to paste into the focused app | `command -v wtype` |

```bash
sudo pacman -S voxtype-bin jq curl sed wl-clipboard wtype
```

Optional: `ollama` (the `qwen` stage — without it, `sed` and `gemini` still
work), and `ffmpeg` + `python3`, which only `bin/hermes-voxtype-transcribe`
needs — along with a voxtype build carrying the `transcribe` subcommand.
`./install` also uses `python3` to check that the `config.toml` it wrote still
parses, and skips that check when it is absent.

### A Nerd Font carrying the Material Design Icons block

Every glyph in `Model.js` is an astral MDI codepoint (`U+F0001`–`U+F1AF0`,
Nerd Fonts 3.x). The widget inherits the bar's font family — `Panel.qml:26`,
`bar ? bar.fontFamily : Style.font.family` — so on a bar whose font lacks that
block, the bar icon, all four panel controls and both history buttons render as
tofu boxes. Nothing else breaks; it just becomes unreadable.

```bash
# every glyph this plugin draws, in one query — needs at least one hit
fc-list ":charset=f036c f0451 f08ae f015f f0cb4 f02da f018f" family | head
```

`f036c` microphone · `f0451` regex (`sed`) · `f08ae` expansion card (`qwen`) ·
`f015f` cloud (`gemini`) · `f0cb4` parachute (fallback) · `f02da` history ·
`f018f` copy. On the reference machine 18 installed families match; the bar font
there is BerkeleyMono Nerd Font.

### Omarchy / Quickshell

The QML imports `qs.Commons` and `qs.Ui`, and instantiates `Panel`,
`BorderSurface`, `Style`, `Color` and `Util` — omarchy-shell internal types, not
public Quickshell API. This was built against **Omarchy 4.0.0.alpha with
Quickshell 0.3.1**. On an older shell those types may not exist, in which case
the widget fails to load and the rest of your bar keeps working. **Not tested
below that version.** The wrapper (`bin/voxtype-punct`) has no such dependency —
it is a plain bash script and works with no Omarchy at all.

---

## Choose your language

Decide this before you install anything else. Language shows up in three
independent places, and getting the third one wrong silently corrupts correct
text.

### 1. The ASR side — `config.toml`

```toml
[whisper]
language = "auto"
```

`auto` is what ships. Pinning it to your language (`"en"`, `"de"`, `"pt"`)
gives the recogniser less to guess at.

**Two caveats, both verified:**

- The key lives under `[whisper]`. With `engine = "parakeet"` — the shipped
  default — it is **inert**: the binary's `ParakeetConfig` has no language
  field, so `voxtype config` echoes the value back and nothing acts on it. What
  decides your output language is the Parakeet model. `parakeet-tdt-0.6b-v3`
  transcribes Brazilian Portuguese every day on the reference machine despite
  voxtype's own bundled README listing Parakeet as English-only, and its vocab
  is not English-only either — 1295 of its 8193 tokens contain a Latin accented
  character, 398 of them a Portuguese one:

  ```bash
  V=~/.local/share/voxtype/models/parakeet-tdt-0.6b-v3/vocab.txt
  grep -cP '[\x{00C0}-\x{024F}]' "$V"                  # -> 1295
  grep -cP '[áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇ]' "$V"         # -> 398
  ```

  The daily use is the evidence; the counts only say the vocabulary has room for
  it. Neither is a promise about *your* language — try it.
- voxtype never validates the value. `voxtype --language zzz config` prints
  `language = Single("zzz")` and exits 0. A typo is accepted in silence.

If your language really is not covered by the Parakeet model, switch to the
Whisper lane (see step 1 of the install), where `language` does take effect.

### 2. The polish prompt

`config/polish-prompt.txt` ships language-agnostic. It tells the model, in
English, to answer in the *input's* own language and never to translate. It
works for any language out of the box.

`config/polish-prompt.pt-BR.txt` is the worked example of a **tuned** prompt:
same rules, written in Portuguese, naming the exact mistakes the author's setup
makes (`"Ento"→"Então"`, `"voce"→"você"`) and the colloquialisms that must
survive (`pra`, `tô`, `cê`, `a gente`, `né`). Tuning wins on accuracy — a prompt
written in your language, listing your recogniser's actual failure modes, beats
the generic one. Copy the pt-BR file as a template, not as-is.

Both LLM stages read this file. The `gemini` stage refuses to run without it;
the `qwen` stage sends it too, unless you turn that off with
`LLM_SEND_SYSTEM = 0` in `llm.conf` because your model already has the same
instructions baked in (`config/vp-qwen.Modelfile` does).

### 3. The `sed` rules

The `sed` stage runs a plain sed script over the transcript before any LLM sees
it — deterministic repairs for words your recogniser reliably mangles.

**By default there is no rules file, and the stage is a no-op pass-through.**
That is deliberate: a regex list is the one part of this pipeline that cannot
know what language it is looking at.

Two examples ship:

| File | What it is |
|---|---|
| `config/polish-sed.example.sed` | Language-neutral starter: a commented template, three safe whitespace rules, and the rules of thumb for writing your own. |
| `config/polish-sed.pt-BR.sed` | The author's real pt-BR rule set, kept verbatim as a worked example. |

> **Do not enable `polish-sed.pt-BR.sed` unless you dictate in Brazilian
> Portuguese.** It contains `s/\band\b/e/g`, which rewrites the English
> conjunction "and" into the Portuguese "e". The rule above it protects a
> hardcoded list of 21 English bigrams (`drag and drop`, `rock and roll`, …) and
> nothing else — `bread and milk` becomes `bread e milk`, in silence, with no
> log line. It also contains `s/\b[Ff]or example\b/por exemplo/gI`, which
> translates outright. Danish and Norwegian *and* ("duck") and Turkish *and*
> ("oath") are hit too.

Rules require **GNU sed**, and the stage runs them as `sed --sandbox -E -f`.
Sandbox mode rejects GNU sed's `e` (execute a shell command), `r` (read a file)
and `w` (write a file), so a rules file is data and never a program — which is
what makes it safe to point `VOX_SED_RULES` at a file you did not write. A rules
file that uses one of them fails as a whole and the text passes through
untouched. Nothing in either shipped example uses them.

A malformed script cannot cost you a dictation, and neither can a destructive
one: the wrapper checks sed's exit status *and* rejects an output that came back
empty (a `d` or `s/.*//` rule), returning the input intact in both cases.

### If you dictate in X, do Y

| You dictate in | `config.toml` `language` | Prompt | `polish-sed.sed` |
|---|---|---|---|
| **Brazilian Portuguese** | `"pt"` (inert on Parakeet; set it anyway for the day you switch engines) | `cp config/polish-prompt.pt-BR.txt ~/.config/voxtype/polish-prompt.txt` | `cp config/polish-sed.pt-BR.sed ~/.config/voxtype/polish-sed.sed` |
| **English** | `"en"` | `cp config/polish-prompt.txt ~/.config/voxtype/` — works as shipped | leave absent (no-op), or start from `polish-sed.example.sed`. **Never** the pt-BR file |
| **Any other single language** | your ISO code | ship `polish-prompt.txt` first; translate + tune it once you see what your recogniser gets wrong | start from `polish-sed.example.sed`, add repairs as you hit them |
| **Two or more, mixed in one dictation** | `"auto"` | `polish-prompt.txt` as shipped — it is explicitly told to keep a mixed input mixed | leave absent. Every rewrite rule is a language bet, and you are not making one |
| **A language Parakeet does not cover** | your ISO code, **and** switch to the Whisper engine | as above | as above |

---

## Install from scratch

`./install` is the shortcut. It is idempotent — run it as often as you like —
and every one of its eight steps reports `OK`, `SKIP`, `WARN`, `NEED` or `FAIL`.
It exits 0 when the install did its job, 1 if any step reported `FAIL`, and 2 on
a bad option; a `NEED` line ("you have not installed voxtype yet") is a fact
about your machine, not an installer failure, and does not change the exit code.
Start with `./install --dry-run`, which prints every mutation it would make and
performs none of them.

What it does: checks for the commands this setup needs; installs
`bin/voxtype-punct` (and the batch helper) into `~/.local/bin`; installs
`config/polish-prompt.txt`; writes a default `polish-mode` of `sed`; wires the
absolute `post_process` path into `config.toml`, backing up what was there and
verifying the result still parses as TOML; and symlinks the repo to
`~/.config/omarchy/plugins/local.voxtype`. Paths follow `XDG_CONFIG_HOME` and
`XDG_STATE_HOME`, exactly as the wrapper does.

What it deliberately does **not** do:

- **Install packages.** It only tells you what is missing.
- **Touch `gemini.key` or `llm.key`.** Your credentials are yours.
- **Write into `~/.config/omarchy/shell.json`.** That is Omarchy's file and a
  bad edit there breaks the whole bar, so enabling the plugin stays a printed
  step you run yourself.
- **Overwrite a `config.toml` that already wires up a post-processor**, or touch
  one that does not parse to begin with.
- **Install a sed rules file.** No rules is the correct default — see "Choose
  your language".
- **Replace a real directory at `~/.config/omarchy/plugins/local.voxtype`.** If
  it finds one it refuses and tells you how to move it aside; see step 7.
- Download a model, configure ollama, or edit `~/.config/hypr/bindings.lua`.

Those are decisions, not steps. Read the manual sequence below at least once —
the verification commands are the point.

### 1. voxtype, and an engine that runs on your hardware

On Omarchy, `voxtype-bin` comes from Omarchy's own pacman repo (`expac -S '%r'
voxtype-bin` → `omarchy`). On plain Arch the same package is on the AUR
(**unverified** — not exercised here).

```bash
sudo pacman -S voxtype-bin jq curl sed wl-clipboard wtype
```

`jq` and `curl` are hard dependencies of the wrapper, not optional. Without
`jq`, both LLM stages silently produce empty request bodies and the history
never gets written — and `sed` still runs, so the breakage is easy to miss.
`wl-copy` is needed by the plugin's history window as well as by voxtype.

Then pick a backend. `/usr/bin/voxtype` is a generated dispatch wrapper owned by
no package; `voxtype setup onnx --enable` and `voxtype setup gpu --enable` both
rewrite it, which is why the two disagree (see Troubleshooting).

```bash
# NVIDIA, Parakeet on CUDA — what this repo is tuned for
sudo pacman -S cuda cudnn nvidia-open-dkms nvidia-utils   # driver 580+ required
sudo voxtype setup onnx --enable

# AMD: picks voxtype-onnx-migraphx, also needs rocm-hip-runtime + migraphx
# CPU / Intel: picks voxtype-onnx-avx512 or -avx2, Parakeet on CPU
# Whisper via Vulkan (works on NVIDIA/AMD/Intel):
#   sudo pacman -S vulkan-icd-loader && sudo voxtype setup onnx --disable
```

**Verify:**

```bash
voxtype setup onnx --status     # -> "Active engine: Parakeet / Backend: ONNX (CUDA 13)"
voxtype info variants           # -> "Binary: .../voxtype-onnx-cuda-13"
```

### 2. The model

```bash
voxtype setup --download --model parakeet-tdt-0.6b-v3
```

Interactive alternatives: `voxtype setup model` or the full `voxtype configure`
TUI. The download itself was **not** run during this write-up.

**Verify:**

```bash
voxtype setup check     # -> "✓ Model 'parakeet-tdt-0.6b-v3' installed (2432 MB)"
                        # -> "✓ All checks passed!"
```

That 2432 MB is where the "about 2.4 GiB on disk" figure comes from — it is
`setup check` reporting an already-downloaded model on the reference machine.
`voxtype setup --help` prints no size for any model, only the name list.

Note `voxtype setup model --list` lists **Whisper** models only and will not
mention your Parakeet model. Trust `setup check`.

### 3. The wrapper and the config

```bash
mkdir -p ~/.config/voxtype
install -Dm755 bin/voxtype-punct ~/.local/bin/voxtype-punct
cp config/config.toml.example ~/.config/voxtype/config.toml
cp config/polish-prompt.txt ~/.config/voxtype/          # or your tuned copy
echo 'sed' > ~/.config/voxtype/polish-mode              # offline default
```

Then open `~/.config/voxtype/config.toml` and fix one line — the placeholder
username in the `[output.post_process]` command:

```toml
command = "/home/YOUR_USERNAME/.local/bin/voxtype-punct"
```

**The path must be absolute.** voxtype expands neither `~` nor `$HOME` here, and
on any failure it falls back **silently** to the raw transcript. Do this by hand
or with `./install`, which substitutes the path in bash and re-reads the line to
confirm — a scripted `sed -i` is a trap, because `&`, `\`, `"` and `#` are all
metacharacters in either sed's replacement or TOML's string syntax, and a home
directory containing one produces a `config.toml` that no longer parses.

`sed` is the deliberate starting pipeline, and it is what `./install` writes: one
offline stage that is a no-op until you give it rules. It is never `auto` or
anything containing `gemini`, because that would ship every word you dictate to
a third party before you ever agreed to it. Move up to `sed+qwen` once your
local model is running (step 5), and to `sed+qwen+?gemini` only once you have
decided you want the cloud fallback (step 6). The bar plugin edits the same file.

Then install a sed rules file **only if you decided to** — see "Choose your
language". No file means the stage is a no-op, which is the correct default.

**Verify:**

```bash
grep '^command' ~/.config/voxtype/config.toml   # must be a real, absolute path
ls -l "$(grep -oP '(?<=^command = ")[^"]+' ~/.config/voxtype/config.toml)"

printf 'hello world' | VOX_TRACE=1 VOX_NO_HISTORY=1 ~/.local/bin/voxtype-punct
```

`VOX_NO_HISTORY=1` is on every verification command in this README on purpose:
without it your test sentences are appended to the permanent dictation log
described under [Privacy](#privacy). The trace goes to **stderr**, the text to
**stdout**.

With the `sed` pipeline and no rules file, the output is `hello world`,
unchanged — that *is* the success case, and the trace tells you so:

```
PIPE=sed
run   sed
  sed sem regras (/home/you/.config/voxtype/polish-sed.sed) — passa direto
```

> **The `VOX_TRACE` output is in Brazilian Portuguese**, as are the panel and
> the history window. The strings are the author's and they stay; this README
> glosses each one you are told to look for. Here:
> `sed sem regras (…) — passa direto` = "sed: no rules file, passing the text
> straight through". A full list is under
> [Reading the trace](#reading-the-trace).

Printing *nothing at all* means you ran the wrong file. If the path in
`config.toml` is wrong, **voxtype tells you nothing** — it just silently types
the raw transcript. That is the single most likely misconfiguration in this
project and it has no symptom other than absent punctuation.

### 4. The systemd user service

```bash
voxtype setup systemd                 # writes ~/.config/systemd/user/voxtype.service
systemctl --user daemon-reload
systemctl --user enable --now voxtype
```

Optional, NVIDIA multi-GPU only:

```bash
mkdir -p ~/.config/systemd/user/voxtype.service.d
cp config/systemd/gpu.conf ~/.config/systemd/user/voxtype.service.d/
systemctl --user daemon-reload && systemctl --user restart voxtype
```

`gpu.conf` sets `VOXTYPE_VULKAN_DEVICE=nvidia`, which is the **Vulkan/Whisper**
device selector. Parakeet-on-CUDA picks its device through `gpu_device` /
`VOXTYPE_GPU_DEVICE` instead, so on the shipped configuration this drop-in is
almost certainly a no-op (**not A/B tested**). Do not credit it with your GPU
acceleration. On AMD or Intel, skip it.

Also: you need to be in the `input` group for the modifier-release guard that
stops the still-held `SUPER+CTRL` of `SUPER+CTRL+X` from corrupting the
synthetic `shift+insert`.

```bash
sudo usermod -aG input "$USER"   # log out and back in
```

**Verify:**

```bash
systemctl --user is-active voxtype     # -> active
voxtype status                         # -> idle
id -nG | tr ' ' '\n' | grep -x input   # -> input
```

Restart the service after **every** `config.toml` edit.

### 5. The `qwen` stage (optional, but it is what makes this fast)

The stage named `qwen` is not "ollama on this machine" — it is *your* LLM
endpoint, declared in `<config>/llm.conf`. Local ollama is only the default.

```bash
cp config/llm.conf.example ~/.config/voxtype/llm.conf   # then edit it
```

For a local ollama, the shipped defaults already match and you can skip the file
entirely:

```bash
# NVIDIA / AMD / neither — pick ONE of the accelerator packages
sudo pacman -S ollama ollama-cuda      # NVIDIA (CUDA)
sudo pacman -S ollama ollama-rocm      # AMD (ROCm)
sudo pacman -S ollama                  # CPU only, or Intel — works, just slower

sudo systemctl enable --now ollama
ollama pull qwen2.5:7b
ollama create vp-qwen7 -f config/vp-qwen.Modelfile
```

`ollama-cuda` is NVIDIA-only; installing it on an AMD or CPU box gets you
nothing. Note also that `config/config.toml.example` sets `flash_attention` and
`gpu_isolation` to `true`, which are **CUDA-build specific** — set both to
`false` on AMD, Intel or CPU. Those two are about voxtype's Whisper lane, not
about ollama, but they come from the same reference machine and they are the
other place a non-NVIDIA setup needs a hand edit.

On a card smaller than **~10 GB**, point the Modelfile at `FROM qwen2.5:3b`
instead (1.9 GB) — `vp-qwen7` is 6.6 GB resident and its 32k context needs KV
cache on top. (`./install` prints the same number in its manual step 2.)

If you already had a `vp-qwen7` from a previous, language-specific Modelfile,
`ollama create` overwrites it — do it, or the local stage will keep following
its old baked-in instructions. See the measurement under "Who owns which file".

Set `OLLAMA_KEEP_ALIVE=-1` if you want the first dictation after an idle stretch
to be fast. This is load-bearing, not a nicety: without it ollama unloads after
five minutes, and the next dictation pays the model load inside the wrapper's
15 s budget, times out, and falls through to whatever is next in your spec with
no indication that anything went wrong. The cost is that it pins the VRAM
forever, which is hostile on an 8 GB card.

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d
printf '[Service]\nEnvironment="OLLAMA_KEEP_ALIVE=-1"\n' | \
  sudo tee /etc/systemd/system/ollama.service.d/keepalive.conf
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

The reference machine also sets `OLLAMA_HOST=0.0.0.0:11434`, so that other
machines can use it as their `LLM_URL`. **Do not copy that by reflex** — plain
ollama has no authentication, so binding it to every interface exposes an
unauthenticated LLM to your whole LAN. Only on a network you trust, or behind a
VPN.

**Verify:**

```bash
curl -s http://localhost:11434/api/tags | jq -r '.models[].name' | grep vp-qwen7
ollama ps        # -> vp-qwen7:latest  6.6 GB  100% GPU  32768  Forever

printf 'hello world this is a test' | \
  VOX_TRACE=1 VOX_NO_HISTORY=1 VOX_MODE=sed+qwen ~/.local/bin/voxtype-punct
```

You want `run qwen` followed by `  ok  qwen` in the trace, and punctuated text
on stdout — measured here, `Hello, world. This is a test.` `FAIL qwen (text
intacto)` ("qwen failed, text unchanged") means the model name or the endpoint
is wrong — and note the text still comes out, unpolished. That is the whole
design.

### 6. The cloud stage (optional)

The wrapper calls the **Gemini Developer API** (Google AI Studio), not Vertex
AI. Create a key at `aistudio.google.com` → *Get API key*. (The Google Cloud
project / billing / quota side of key creation was **not** verified.)

```bash
install -m 600 /dev/null ~/.config/voxtype/gemini.key
printf '%s' 'YOUR_AI_STUDIO_KEY' > ~/.config/voxtype/gemini.key
```

Only the **first line** of that file is used, so a stray trailing newline is
fine and a second line is ignored rather than smuggled into the request headers.

**Verify:**

```bash
stat -c '%a %n' ~/.config/voxtype/gemini.key    # -> 600
printf 'hello world this is a test' | \
  VOX_TRACE=1 VOX_NO_HISTORY=1 VOX_MODE=sed+gemini ~/.local/bin/voxtype-punct
```

This one really does send that sentence to Google. The stage aborts *before*
making any request if the key file is missing/empty, or if `polish-prompt.txt`
is missing/empty. The second one is deliberate: without a system prompt Gemini
*answers* your dictation instead of punctuating it.

### 7. The bar plugin

Third-party Omarchy plugins live in `~/.config/omarchy/plugins/<id>/`, exactly
one directory level down, and the catalog scan follows symlinks — so a symlink
is the supported way to run this from a checkout. `manifest.json` sits at the
repo root precisely so this works.

**`ln -s` does not fail when the destination already exists as a directory.** It
silently creates the link *inside* it, one level too deep, where Omarchy's
catalog scan (`find -L "$user_dir" -mindepth 2 -maxdepth 2 -type f -name
manifest.json`) will never see it — and every verification below still passes,
against the stale copy. If you installed this plugin by copying before the repo
existed, that directory is there. Guard the link:

```bash
PL=~/.config/omarchy/plugins/local.voxtype

# an existing REAL directory is a previous copy-install: move it aside first
if [ -e "$PL" ] && [ ! -L "$PL" ]; then mv "$PL" "$PL.bak.$(date +%s)"; fi

mkdir -p ~/.config/omarchy/plugins
ln -sfn "$PWD" "$PL"

# prove the link points at THIS checkout, not at something nested
readlink -f "$PL"        # must print exactly: the repo path you ran this from

omarchy-shell shell rescanPlugins    # the running bar has not seen the new dir
omarchy plugin enable local.voxtype
```

Or just run `./install`, which refuses to touch a real directory there and tells
you the same two commands.

The `rescanPlugins` call is not optional. `omarchy plugin enable` does not look
at the filesystem — it resolves the id against the *running* shell's plugin
registry, which was populated at shell startup. Without a rescan you get
`omarchy-plugin-enable: plugin 'local.voxtype' is not known; run: omarchy-shell
shell rescanPlugins`. Enabling writes `{"id": "local.voxtype"}` into the bar
layout of `~/.config/omarchy/shell.json` — that entry *is* what makes the plugin
enabled.

**Verify:**

```bash
omarchy plugin list | grep local.voxtype    # -> local.voxtype  enabled  third-party  bar-widget
jq -r '.bar.layout | to_entries[] | .value[].id' ~/.config/omarchy/shell.json | grep local.voxtype
```

Then look at your bar. Left-click the icon: the pipeline panel opens.

> **If you validate, pass a trailing slash.** `omarchy plugin validate` refuses
> any symlink inside a plugin folder, and it counts a symlinked plugin directory
> itself as one — so validating a checkout linked into place fails unless the
> path ends in `/`:
>
> ```bash
> omarchy plugin validate ~/.config/omarchy/plugins/local.voxtype/   # rc=0, silent
> omarchy plugin validate ~/.config/omarchy/plugins/local.voxtype    # exits 1
> ```
>
> This is why nothing in this repo is a symlink, `CLAUDE.md` included — it is a
> real file pointing at `AGENTS.md` rather than a link to it. The running shell
> has no such rule (`PluginRegistry.qml` does not check), so a plugin that fails
> this lint still loads; validate is a lint of the folder, not a test of the
> install. Success is silent: rc=0 and no output.

### 8. The history keybinding

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + V", "Dictation history", "omarchy-shell voxtype-history toggle")
```

The IPC target is `voxtype-history`, declared inside `History.qml` and
deliberately independent of the plugin id — so renaming the plugin does not
break this binding. **It does require the bar plugin from step 7 to be
enabled**, though: the `IpcHandler` lives inside the `History` instance that
`Panel.qml` declares, and `Panel.qml` is the bar widget. With the plugin
disabled the target is never registered and the keybinding does nothing at all —
no window, no error.

The target has four functions, and `copyLast` is worth its own key: it copies
the most recent dictation to the clipboard without opening anything.

| `omarchy-shell voxtype-history …` | Does |
|---|---|
| `open` | open the history window |
| `close` | close it |
| `toggle` | the one to bind to `SUPER+SHIFT+V` |
| `copyLast` | copy the latest dictation to the clipboard, no window |

**Verify:**

```bash
omarchy-shell voxtype-history toggle
```

The window should appear centred on your focused monitor. Press `Esc`.

### 9. End to end

```bash
voxtype setup check
voxtype status                 # -> idle
```

Hold `F9`, say something, release. Watch the text arrive in the focused app.

---

## Configuration

### `config.toml` — the keys that matter, and why

Full annotated file: `config/config.toml.example`. Per-file copy instructions
for everything in `config/` are in [`config/README.md`](config/README.md). The
values below were measured on the reference machine; the comments explain the
*reasoning*, which is what transfers.

| Key | Value | Why |
|---|---|---|
| `engine` | `"parakeet"` | Parakeet-tdt-0.6b-v3 on CUDA. Change to `"whisper"` if you switched backends in step 1 — `voxtype config set engine whisper` is the only key `config set` accepts. |
| `state_file` | `"auto"` | Required for `voxtype record` and `voxtype status` to work at all. Resolves to `$XDG_RUNTIME_DIR/voxtype/state`. |
| `[hotkey] enabled` | `false` | voxtype does not grab `/dev/input` itself; Hyprland sends `voxtype record` signals. The `key = "HOME"` line next to it is a dead leftover that `voxtype config` still echoes back. |
| `[audio] max_duration_secs` | `60` | A hard cap on one dictation. Anything past 60 seconds is cut off — raise it if you dictate in long stretches. |
| `[output] mode` | `"paste"` | **The important one.** `"type"` used wtype at 1 ms per character; with fcitx5 active every synthetic keystroke goes through the input engine, and the race scrambled text — cursor jumping back to the start, characters landing in the middle of what was already written. Paste sidesteps the entire path: one clipboard write, one keystroke. |
| `paste_keys` | `"shift+insert"` | Not `ctrl+v`, because terminals do not paste with `ctrl+v`. Ghostty only binds `shift+insert` and `ctrl+shift+v`; a `ctrl+v` passes through the terminal into the app, and inside Claude Code `ctrl+v` is *paste image* — with text on the clipboard it does nothing at all. `shift+insert` also pastes in GTK, Chromium and Electron, so it is the one key that works everywhere, which is what this option has to be. |
| `restore_clipboard` | `true` | Otherwise every dictation destroys whatever you had copied. |
| `restore_clipboard_delay_ms` | `600` | Has to cover the receiving app reading the clipboard. Apps that read via a subprocess are slow and miss a shorter window. |
| `[output.post_process] command` | absolute path | voxtype expands neither `~` nor `$HOME` here. A wrong path fails **silently** — you get the raw transcript, no error, no log line. |
| `[output.post_process] timeout_ms` | `35000` | voxtype's limit on the whole wrapper. See below. |
| `[whisper] flash_attention`, `gpu_isolation` | `true` | CUDA-build specific. Set `false` on a non-CUDA setup — the example ships them `true` because the reference machine is NVIDIA. |
| `[whisper] model` | `"large-v3-turbo"` | Only consulted when `engine = "whisper"`. |

### The `timeout_ms` cliff

Blowing `[output.post_process] timeout_ms` does **not** degrade gracefully.
voxtype discards the entire post-process — including the deterministic `sed`
stage, which cost nothing — and types the raw Parakeet transcript. Nothing is
logged, no notification fires. You just get unpunctuated text.

Budget for your own spec:

- **15 s per `qwen` step**, by default (`--connect-timeout 1 --max-time 15`).
  Both numbers are settable in `llm.conf`; the connect timeout defaults to 5 s
  instead of 1 s for a non-localhost endpoint.
- **up to 18 s per `gemini` step** (15 s, plus one conditional retry that only
  fires after a *fast* failure)
- plus a second or two of spawn and `jq` margin

`sed+qwen+?gemini` therefore has a true worst case of 15 + 18 ≈ 33 s, which is
what the shipped `35000` covers. A spec like `sed+qwen+gemini+?qwen` has a 48 s
worst case and **will** blow it.

If you run a slower local model, raise `LLM_TIMEOUT` in `llm.conf` **and**
`timeout_ms` in `config.toml` by the same amount. Changing only one guarantees
the failure you were trying to avoid.

### `llm.conf` — where the `qwen` stage sends your text

Full annotated file: `config/llm.conf.example`. Copy it to
`<config>/llm.conf`. Without it the stage posts to a local ollama at
`http://localhost:11434/api/generate` asking for the model `vp-qwen7`.

The file exists because environment variables cannot reach the wrapper: it is
spawned by the voxtype daemon under `systemd --user`, so an `export` in your
shell never arrives. It is **parsed**, never sourced — `KEY = value` one per
line, `#` comments, optional quotes — so a config file can never become a script
that runs on every dictation.

| Key | Default | What it does |
|---|---|---|
| `LLM_URL` | `http://localhost:11434/api/generate` | Any HTTP endpoint you can reach: this box, a machine on your LAN, the far end of a VPN, a paid API. |
| `LLM_MODEL` | `vp-qwen7` | The model name as that endpoint knows it. |
| `LLM_API` | deduced from the URL path | `ollama` (`/api/generate`), `ollama-chat` (`/api/chat`) or `openai` (`/chat/completions`). Set it explicitly for a nonstandard path. |
| `LLM_KEY_FILE` | `<config>/llm.key` | File holding a bearer token, for an endpoint that wants one. No header is sent when the file is absent or empty; only the first line is used. **Write an absolute path** — the parser does no `~` expansion. |
| `LLM_SEND_SYSTEM` | `1` | Send `polish-prompt.txt` as the system prompt. Turn it off only for a model that already carries those instructions, such as one built from `config/vp-qwen.Modelfile`. |
| `LLM_TIMEOUT` | `15` | Seconds for the whole response. Raising it above ~20 means raising `timeout_ms` too. |
| `LLM_CONNECT_TIMEOUT` | `1` on localhost, `5` elsewhere | Seconds for the TCP connect. |
| `GEMINI_MODEL` | `gemini-flash-latest` | The separate cloud stage's model id. That stage always talks to Google and has its own key file. |

Pointing `LLM_URL` at another machine is a privacy decision of the same kind as
enabling `gemini` — the "`qwen` is offline" guarantee in this README is a
statement about the shipped default, not about whatever you put in this file.

### Plugin settings — `~/.config/omarchy/shell.json`

The minimum is `{ "id": "local.voxtype" }`, as an entry in `bar.layout.left`,
`.center` or `.right`. Everything else is optional:

```json
{
  "id": "local.voxtype",
  "modePath": "/home/you/.config/voxtype/polish-mode",
  "colorize": true,
  "modeColors": { "off": "#a55555" }
}
```

| Key | Type | Default | What it does |
|---|---|---|---|
| `modePath` | string | `~/.config/voxtype/polish-mode` | The file holding the current spec. The widget reads it (watched, so `echo local > polish-mode` updates the bar immediately) and writes it atomically. Set it explicitly if you have moved `XDG_CONFIG_HOME` — the widget does not read that variable, the wrapper does. |
| `colorize` | boolean | `true` | Whether your `modeColors` overrides are honoured. Accepts `true/false`, `"1"/"0"`, `"yes"/"no"`, `"on"/"off"`, because `shell.json` values arrive as raw JSON. |
| `modeColors` | object | `{}` | Per-key icon colour overrides. |

Two gotchas worth knowing before you fight these:

- **`colorize: false` does not turn colouring off.** It only suppresses *your*
  overrides; the built-in theme-derived tint (dimmed when the pipeline is `off`)
  still applies.
- **`modeColors` keys mean two different things.** In the bar the lookup key is
  the whole pipeline spec (`"off"`, `"sed+qwen"`, `"sed+qwen+?gemini"`); inside
  the panel it is a stage key (`"sed"`, `"qwen"`, `"gemini"`). So
  `{"gemini": "…"}` tints a panel row and never the bar icon, and `{"auto": "…"}`
  matches nothing anywhere, because aliases are normalised away before the
  lookup.
- **`barWidget.defaults` in `manifest.json` is catalog metadata only.** It is
  never merged into the settings the widget receives — every default is
  re-applied by hand in `Service.qml`. If you fork this, do not assume a value
  listed under `defaults` will arrive.

---

## The pipeline spec

The "mode" is not a preset name. It is an ordered list of stages joined by `+`,
executed left to right, repeats allowed.

```
spec  := token ( '+' token )*
token := [ '?' ] stage
stage := 'sed' | 'qwen' | '3090' | 'gemini'
```

| Element | Meaning |
|---|---|
| `sed` | Deterministic regex fixes from your rules file. Offline. Adds no punctuation. **Never fails.** |
| `qwen` | Your LLM endpoint from `llm.conf` — a local ollama (`vp-qwen7` on `localhost:11434`) unless you changed it. |
| `3090` | Token-level alias for `qwen`, kept for backward compatibility. |
| `gemini` | Google Generative Language API. **Your text leaves the machine.** |
| `+` | Stage separator. Order is literal, left to right. |
| `?` prefix | "Run only if the step **immediately above** failed." |

`?` is a **per-step** fallback, not "some LLM already succeeded". A *skipped*
fallback step deliberately does not update the success flag, so reserves chain
in order: in `qwen+?gemini+?sed`, if both LLMs fail, sed still rescues the text.

Two stages in a row **without** `?` means two chained LLM passes over the same
text — the second polishes the first one's output. That is a legitimate choice,
not a bug.

Five legacy names survive as whole-string aliases so an old `polish-mode` keeps
working:

```
off = <nothing>   local = sed   3090 = sed+qwen   gemini = sed+gemini   auto = sed+qwen+?gemini
```

### Worked examples

Verified by running the script with `VOX_TRACE=1 VOX_NO_HISTORY=1`.

| `VOX_MODE` / `polish-mode` | Resolved pipeline | What happens |
|---|---|---|
| `off` | *(empty)* | Nothing runs. Raw transcript, verbatim. |
| `local` | `sed` | sed only |
| `3090` | `sed qwen` | whole-string alias |
| `gemini` | `sed gemini` | whole-string alias |
| `auto` | `sed qwen ?gemini` | the alias that keeps the cloud fallback |
| *(unset / file missing / file empty)* | `sed qwen` | **failure-safe default — see below** |
| `sed+3090` | `sed qwen` | here `3090` is a **token**, not the preset |
| `3090+sed` | `qwen sed` | **not** the preset — no leading `sed` |
| `sed+qwen+gemini` | `sed qwen gemini` | two LLM passes, gemini works on qwen's output |
| `sed+gemini+?qwen` | `sed gemini ?qwen` | cloud first, local in reserve |
| `qwen+?gemini+?sed` | `qwen ?gemini ?sed` | both LLMs fail → sed rescues |
| `sed+sed` | `sed sed` | repeats are allowed |
| `?gemini` | `gemini` | leading `?` dropped — nothing above can have failed |
| `+gemini` | `gemini` | empty token dropped |
| `OFF`, `  Auto  `, `SED + QWEN` | `off`, `auto`, `sed qwen` | whitespace stripped, lowercased |
| `xyz`, `sed+banana` | `sed qwen` | one invalid token discards the **whole** spec |

Three rules that catch everyone:

- **Only `off` disables polishing, and the fallback never reaches the network.**
  A missing file, an empty file, a truncated write from the panel, a typo — all
  fall back to `sed+qwen`, never to raw text and never to anything containing
  `gemini`. Losing punctuation in silence is worse than running a default; so is
  having an accident promote you to sending every dictation to Google. Writing
  `auto` explicitly is how you ask for the cloud fallback.
- **`?` right after `sed` is dead code.** `sed` never fails, so `sed+?gemini`
  never calls Gemini. Put `?` after `qwen` or `gemini` only.
- **Appending to a preset name loses the preset's implicit `sed`.**
  `3090+gemini` is `qwen+gemini`, with no sed step at all. Write the stages you
  want explicitly.

> **Known divergence:** the wrapper's failure-safe default is `sed+qwen`, but
> `Model.js` still has `DEFAULT_MODE = "sed+qwen+?gemini"`. With no `polish-mode`
> file at all, the bar therefore *displays* `sed → qwen ⇢ gemini` while the
> wrapper *runs* `sed+qwen`. Writing anything from the panel resolves it, and so
> does `echo 'sed+qwen' > <config>/polish-mode`.

### Failure policy

`text` always holds the best result so far. A stage that fails simply does not
assign to it, so losing a dictation is structurally impossible.

| Condition | Result |
|---|---|
| Empty stdin | exits immediately, nothing written, no history entry |
| LLM endpoint unreachable / timeout / bad JSON | stage fails, text untouched |
| Gemini: no key, empty key, or missing `polish-prompt.txt` | stage aborts **before** the request |
| LLM returns whitespace only, or the string `null` | rejected, text untouched |
| LLM output < 60 % of its input length | rejected as a summary/truncation, text untouched |
| `sed` rules file missing, empty, unreadable or malformed | pass-through, and still counts as **success** |
| `sed` rules use `e`, `r` or `w` (rejected by `--sandbox`) | whole script fails, pass-through, still **success** |
| `sed` rules empty the text (`d`, `s/.*//`) | rejected, input returned intact, still **success** |
| `jq` missing | both LLM stages and the history silently die; `sed` still runs |
| History write fails, for any reason | ignored |

The **60 % floor** exists for a measured incident: on a long dictation the LLM
summarised instead of punctuating — 2760 characters in, 143 out, 95 % of the
dictation destroyed, accepted with no warning. Punctuating never shortens text
meaningfully, so anything under 60 % is a summary. It is 60 % rather than 90 %
so a preceding `sed` that expanded an abbreviation cannot cause a false reject.
There is **no upper bound**, so an LLM that answers your dictation instead of
punctuating it produces a longer string and is accepted.

### Environment variables

These are for **testing from a shell**. The daemon spawns the wrapper under
`systemd --user`, so an `export` in your terminal does not reach a real
dictation — for a persistent change, edit `llm.conf` or add a
`voxtype.service.d` drop-in. Precedence for the LLM endpoint is
environment > `llm.conf` > default.

| Name | Default | Effect |
|---|---|---|
| `VOX_MODE` | contents of `<config>/polish-mode` | The spec. **An empty value falls through to the file** (`:-`), so `VOX_MODE=""` does not mean "no mode" — use `VOX_MODE=off`. |
| `VOX_TRACE` | unset | Any non-empty value prints `PIPE=…`, `run`/`skip`/`ok`/`FAIL` to **stderr**, in Portuguese. stdout stays text-only. |
| `VOX_SED_RULES` | `<config>/polish-sed.sed` | Path to the sed rules script. |
| `VOX_NO_HISTORY` | unset | Any non-empty value disables the history file entirely. **Set this on every test.** |
| `VOX_HISTORY` | `${XDG_STATE_HOME:-~/.local/state}/voxtype/history.jsonl` | History file path. |
| `VOX_HISTORY_MAX_BYTES` | `1048576` | Size at which the history is pruned. |
| `VOX_HISTORY_KEEP` | `500` | Lines kept when pruning fires. |
| `VOX_LLM_CONF` | `<config>/llm.conf` | Path to the endpoint config file. |
| `VOX_LLM_URL` (or legacy `OLLAMA_URL`) | `llm.conf`, then `http://localhost:11434/api/generate` | `qwen` stage endpoint. |
| `VOX_LLM_MODEL` (or legacy `OLLAMA_MODEL`) | `llm.conf`, then `vp-qwen7` | `qwen` stage model name. |
| `VOX_LLM_API` | deduced from the URL | `ollama`, `ollama-chat` or `openai`. |
| `GEMINI_MODEL` | `gemini-flash-latest` | Gemini model id in the endpoint path. |

`LLM_KEY_FILE`, `LLM_TIMEOUT`, `LLM_CONNECT_TIMEOUT` and `LLM_SEND_SYSTEM` are
settable in `llm.conf` only, not from the environment. The Gemini key path
(`<config>/gemini.key`) and the prompt path (`<config>/polish-prompt.txt`) are
not overridable at all.

### Reading the trace

`VOX_TRACE=1` prints in Brazilian Portuguese. Every line you are likely to see,
glossed:

| Trace line | Means |
|---|---|
| `PIPE=sed qwen ?gemini` | the resolved pipeline, after aliases and validation |
| `run   qwen` | this step is being executed |
| `  ok  qwen` | it returned usable text, which replaced the current text |
| `skip  ?gemini (last_ok=1)` | skipped: the step above it succeeded, so the fallback was not needed |
| `  FAIL qwen (text intacto)` | the step failed; **text unchanged** — unreachable endpoint, wrong model name, bad JSON |
| `  FAIL qwen (truncou: 143B de 2760B — text intacto)` | rejected by the 60 % floor: it truncated 2760 bytes to 143; text unchanged |
| `  sed sem regras (…) — passa direto` | no rules file: sed passed the text straight through (the shipped default) |
| `  sed regras inválidas (…) — text intacto` | the rules file did not run — a syntax error, or a `e`/`r`/`w` command `--sandbox` refuses; text unchanged |
| `  sed esvaziou o texto (…) — text intacto` | the rules emptied the text (`d`, `s/.*//`); refused, text unchanged |

---

## The bar plugin, briefly

**The icon tells you where your text goes.** An unconditional `gemini` outranks
everything and shows the cloud glyph, even when a `qwen` runs before it — the
fact worth seeing at a glance is that your dictation leaves the machine on every
utterance, not which model produced the final wording. Then an unconditional
`qwen` wins; then, only if the pipeline has no unconditional LLM step at all,
the first LLM step of any kind, fallback or not.

That last clause is the exception people trip on. `sed+qwen+?gemini` shows the
GPU glyph, because the `qwen` is unconditional. But `sed+?gemini` — whose
`gemini` can never run, since `sed` never fails — shows the **cloud** glyph
anyway, because there is nothing unconditional to outrank it. The icon can
therefore over-report the cloud; it can never under-report it. An unconditional
`gemini` always shows the cloud, which is the direction that matters.

| Input on the bar icon | Effect |
|---|---|
| Left click | Toggle the pipeline editor |
| Right click / scroll down | Next preset |
| Scroll up | Previous preset |
| Middle click | Re-read `polish-mode` from disk |

**Right-click and scroll cycle the five presets only, and a hand-built pipeline
is one scroll away from being replaced by one.** The lookup for a custom spec
returns -1, the widget pretends you were sitting on the default (`sed+qwen+?gemini`,
the last preset in the list) and then steps off it — so from *any* custom
pipeline, a right-click or scroll down lands on `off`, and a scroll up lands on
`sed+gemini`, which sends every dictation to Google. Verified by evaluating
`Model.js`:

```
nextMode("sed+sed", +1) -> "off"        nextMode("sed+sed", -1) -> "sed+gemini"
```

In the **pipeline editor**: chevrons reorder, the parachute toggles fallback
(only from row 2 down — nothing above row 1 can have failed), `x` removes,
`+ sed` / `+ qwen` / `+ gemini` append. Clicking a row's empty space performs
its main action, which for a stage row is *remove*, with no confirmation. The
panel stays open after every edit. `Esc` closes. Digits `1`–`9` act on the row
at that position — so with a three-stage pipeline, `1`–`3` delete and `4`–`6`
add. The first arrow-key press only arms the cursor; it does not move it.

Above the stage list sit **two buttons the pipeline does not own**:
`󰋚 histórico` closes the panel and opens the history window, and
`󰆏 copiar último` copies the most recent dictation straight to the clipboard
without opening anything. The second one is `copyLast` on the `voxtype-history`
IPC target, so you can bind it to a key of its own (step 8).

The **history window** (`SUPER+SHIFT+V`) is a two-pane reader: entry list on the
left, full text of the selection on the right. Type to filter — it is a fake
search field (a `Text` fed raw keystrokes, so there is no `TextField` fighting
for focus), which means you cannot paste into it and `Ctrl+U`, not `Ctrl+A`,
clears it. The filter matches **both** the polished text and the raw transcript,
so searching for what you actually *said* finds the entry even when the LLM
rewrote the sentence. `Enter` or a click copies and closes. At most 60 rows are
rendered; the footer makes the truncation visible — `Enter ou clique copia · Esc
fecha · 60 de 214`, i.e. "60 of 214".

**The panel, the history window and the `VOX_TRACE` output are all in Brazilian
Portuguese.** Everything shipped is language-agnostic *about your dictation* —
the prompt, the sed default, the config — but the author's own interface strings
stay in the author's language. This README quotes the exact strings you should
see and glosses the ones you are told to look for.

---

## Privacy

Two things in this project move your words somewhere you might not expect. Both
are defensible; neither should be a surprise.

### 1. Every dictation is written to disk, by default

`~/.local/state/voxtype/history.jsonl`, one JSON object per line, appended by
the wrapper on **every** dictation — including when the spec is `off`:

```json
{"t":"2026-08-31T14:23:42-03:00","spec":"sed","raw":"what the ASR heard","text":"what got pasted"}
```

- It holds **both** the raw transcript and the final text.
- It is created mode `0600` from the first byte (the file and its prune temp
  file are both created under `umask 077`) — that stops other local users on the
  box, and nothing else. It is **not** encrypted and **not** excluded from
  backups, `rsync`, or a home-directory sync client.
- It self-prunes to the last 500 lines once it passes ~1 MB. That is a size
  cap, not a retention policy.
- Everything you speak into the microphone goes in: passwords read aloud,
  addresses, medical details, someone else's private message.

Disable it by putting `VOX_NO_HISTORY=1` in the environment of whatever launches
voxtype — a systemd user drop-in is the clean way:

```bash
mkdir -p ~/.config/systemd/user/voxtype.service.d
printf '[Service]\nEnvironment="VOX_NO_HISTORY=1"\n' > \
  ~/.config/systemd/user/voxtype.service.d/nohistory.conf
systemctl --user daemon-reload && systemctl --user restart voxtype
```

The plugin's history window then stays empty — it reads that same file. Or point
`VOX_HISTORY` at a path on an encrypted volume. Deleting the file is enough; it
is recreated only if history is still enabled. To destroy what is already in it,
see [Uninstall](#uninstall).

### 2. The `gemini` stage sends your dictation to Google

Any spec containing `gemini` POSTs the full current text to
`generativelanguage.googleapis.com`. Under the `auto` alias (`sed+qwen+?gemini`)
that only happens when the local model failed — but under `sed+gemini` or
`sed+qwen+gemini` it happens on **every single utterance**.

**What is offline:**

| Stage | Network |
|---|---|
| `sed` | none — a local regex script, and `--sandbox` stops the rules file from opening a file or running a command |
| `qwen` | whatever `llm.conf` says. `localhost:11434` by default, which never leaves the machine — but this is the one entry in this table you can change yourself |
| `gemini` | HTTPS to Google, always |

The bar icon is the at-a-glance indicator, in one direction: an unconditional
`gemini` in your pipeline always shows the cloud glyph, so a cloud pipeline can
never look local. The reverse is not guaranteed — a fallback-only pipeline like
`sed+?gemini` shows the cloud glyph too, even though it never reaches the cloud
(see "The bar plugin, briefly"). `off` disables the pipeline entirely and dims
the icon.

If you want a fully offline setup: do not create `gemini.key`, use a spec with
no `gemini` step — `sed+qwen` is the one to use, and it is also what the wrapper
falls back to on its own — and leave `LLM_URL` pointing at localhost.

---

## Security

- **The Gemini key lives in `<config>/gemini.key`, chmod 600, and is never in
  this repo.** Nothing in the repo reads a key from anywhere else, and
  `.gitignore` blocks `*.key` and `*.jsonl`. Check before you ever run
  `git add -A`:

  ```bash
  git check-ignore -v gemini.key history.jsonl
  git status --porcelain -uall
  ```

- **Rotating the key:** create a new one in Google AI Studio, write it over the
  file, revoke the old one in the AI Studio console, then dictate once with
  `VOX_MODE=sed+gemini` to confirm.

  ```bash
  printf '%s' 'NEW_KEY' > ~/.config/voxtype/gemini.key
  chmod 600 ~/.config/voxtype/gemini.key
  printf 'hello world' | VOX_TRACE=1 VOX_NO_HISTORY=1 \
    VOX_MODE=sed+gemini ~/.local/bin/voxtype-punct
  ```

  Rotate immediately if the key has ever been pasted into a chat window, a
  screenshot, a paste service, or a shell history you sync.

- **Neither your API key nor your dictation appears on a command line.** Both
  LLM stages pass their credentials through `curl -H @<(…)` — an anonymous pipe
  visible only inside this process tree — and the request body through stdin
  with `--data-binary @-`. Nothing lands in `/proc/<pid>/cmdline`, where any
  local process could read it. This is why `curl` ≥ 7.55 is a requirement. Only
  the first line of a key file is used, so a malformed key file cannot inject a
  second HTTP header.

- **A sed rules file is data, not a program.** The stage runs `sed --sandbox`,
  which disables GNU sed's `e` (execute), `r` (read file) and `w` (write file)
  commands. Without that, pointing `VOX_SED_RULES` at someone else's rules file
  would be running their code and handing them your dictation.

- **A shell plugin runs unsandboxed inside your session.** This is Omarchy's own
  warning and it applies to this plugin as much as any other: a bar widget is
  QML executing with your user's full privileges, with access to your files and
  your network, for as long as you are logged in. Read what you install. That
  cuts both ways — the code here is short and readable on purpose, and you
  should read it before symlinking it into `~/.config/omarchy/plugins/`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Typed text comes out scrambled, interleaved, or the cursor jumps to the start mid-sentence | `mode = "type"` sends one synthetic keystroke per character; with fcitx5 active each one goes through the input engine and races the app | Use `mode = "paste"` with `paste_keys = "shift+insert"`. This is what the shipped config does and why. |
| Raw, unpunctuated text appears | The post-process was discarded whole. Either `timeout_ms` was blown, or `[output.post_process] command` points at a path that does not exist — both fail **silently** | `grep '^command' ~/.config/voxtype/config.toml` and confirm the absolute path exists. Then check your spec against the 15 s-per-qwen / 18 s-per-gemini budget and raise `timeout_ms`. |
| Punctuation works in the terminal but not from the hotkey | `config.toml` was edited without restarting the daemon | `systemctl --user restart voxtype` |
| Everything renders as empty boxes — bar icon, panel controls, history buttons | The bar's font has no Material Design Icons block; the widget inherits that font | Install a Nerd Font ≥ 3.x and set it as the bar font. Check with `fc-list ":charset=f0cb4" family`. |
| Bar icon does not update when the mode changes | Wrong `modePath` in `shell.json`, or `polish-mode` lives outside `~/.config/voxtype` — the widget also watches the parent directory, but only that one | Middle-click the icon to force a re-read. Confirm with `cat ~/.config/voxtype/polish-mode`, and set `modePath` explicitly if the file is elsewhere. |
| The bar shows one pipeline and the wrapper runs another | Either you moved `XDG_CONFIG_HOME` (the wrapper follows it, the widget does not), or there is no `polish-mode` file at all (the two defaults differ — see "The pipeline spec") | Write the file: `echo 'sed+qwen' > <config>/polish-mode`, and set `modePath` in `shell.json` to that same absolute path. |
| Panel does not appear after install | The plugin id is not in the bar layout, or `manifest.json` is not exactly one directory below `~/.config/omarchy/plugins/` — including the case where `ln -s` nested the link inside an existing directory | `readlink -f ~/.config/omarchy/plugins/local.voxtype` must print your checkout. Then `omarchy-shell shell rescanPlugins` and `omarchy plugin enable local.voxtype`. |
| `omarchy plugin enable` says the plugin *is not known* | The running shell's registry was built before the symlink appeared; `enable` never looks at the filesystem | `omarchy-shell shell rescanPlugins`, then enable again. |
| `omarchy plugin validate` fails with *symlinks are not allowed inside a plugin folder* | You linked the checkout into the plugins directory and left the trailing slash off the path — validate counts the directory symlink itself as a violation | Add the slash: `omarchy plugin validate ~/.config/omarchy/plugins/local.voxtype/`. Cosmetic either way; the running shell has no such rule and loads the plugin fine. |
| `SUPER+SHIFT+V` does nothing at all — no window, no error | The `IpcHandler` lives inside the bar widget, so with the plugin disabled the `voxtype-history` target is never registered | `omarchy plugin enable local.voxtype` (step 7), then try again. |
| `omarchy-shell local.voxtype toggle` stopped working after renaming the plugin | `moduleName` and `ipcTarget` are hardcoded to `"local.voxtype"` in `Panel.qml` | Rename in all four places: `manifest.json` id, the plugin directory, the `shell.json` entry, and `Panel.qml`. `SUPER+SHIFT+V` is unaffected — the history window has its own IPC target. |
| Trace says `FAIL qwen (text intacto)` | The endpoint is down, the model name does not match, or `LLM_URL` is wrong | `systemctl status ollama`; `curl -s localhost:11434/api/tags \| jq -r '.models[].name'`; confirm the name in `llm.conf` (or `vp-qwen7`) is in the list. |
| The local stage translates your dictation into another language | Your installed model's baked-in `SYSTEM` block names a specific language, and `LLM_SEND_SYSTEM = 0` is suppressing the neutral prompt | Remove that line from `llm.conf`, or rebuild the model: `ollama create vp-qwen7 -f config/vp-qwen.Modelfile`. |
| First dictation after a break is slow and falls through to the next stage | ollama unloaded the model after its 5-minute default keep-alive; the reload does not fit in the 15 s budget | Set `OLLAMA_KEEP_ALIVE=-1` (step 5). Costs you the VRAM permanently. |
| Gemini returns *caller does not have permission* | Bad, revoked or wrong-project key; or the Generative Language API is not enabled for it | Re-check the key in AI Studio and rewrite `gemini.key`. The wrapper already retries once automatically, but only when the first failure came back in under 3 s. |
| Gemini stage does nothing at all, instantly | No key file, empty key file, or missing/empty `polish-prompt.txt` — all three abort before any request | `ls -l ~/.config/voxtype/{gemini.key,polish-prompt.txt}`. The prompt check is deliberate: without a system prompt Gemini answers your dictation instead of punctuating it. |
| `voxtype setup check` says the model is not installed | Never downloaded, or you switched engines | `voxtype setup --download --model parakeet-tdt-0.6b-v3`. Note `setup model --list` shows Whisper models only. |
| Long dictations come back unpolished while short ones work | The 60 % length floor rejected the LLM output as a summary | Expected behaviour — the original text is preserved. `VOX_TRACE=1` prints `FAIL qwen (truncou: NB de MB)`. If it fires on legitimate short dictations, that is the known false-positive case. |
| Long dictations are cut off mid-sentence at the source | `[audio] max_duration_secs = 60` in the shipped config | Raise it in `config.toml` and restart the daemon. |
| Words are being replaced with words from another language | A `polish-sed.sed` for the wrong language is installed. `and → e`, `for example → por exemplo` are the pt-BR rules | `rm ~/.config/voxtype/polish-sed.sed` — with no file the stage is a no-op. See "Choose your language". |
| Trace says `sed regras inválidas` on a rules file that used to work | The stage now runs `sed --sandbox`, which refuses the `e`, `r` and `w` commands | Remove the offending rule. A rules file is data, not a program — see Security. |
| The `sed` stage stopped doing anything after an update | Correct. The rules used to be hardcoded in the wrapper and are now external and opt-in | `cp config/polish-sed.pt-BR.sed ~/.config/voxtype/polish-sed.sed` if you dictate pt-BR, otherwise leave it absent. |
| LLM stages never work and there is no error anywhere | `jq` is missing, so every request body comes out empty | `sudo pacman -S jq`. `sed` still runs without it, which is why this is easy to miss. |
| `voxtype info variants` and `voxtype setup gpu --status` disagree about the backend | `setup gpu --status` only reports the Whisper/Vulkan lane and will claim "CPU (native)" while Parakeet runs on CUDA | Trust `voxtype info variants` and `voxtype setup onnx --status`. |
| Parakeet stopped being used after installing via the Omarchy menu | `omarchy-voxtype-install` runs `voxtype setup gpu --enable` when Vulkan is detected, which rewrites the same `/usr/bin/voxtype` dispatch wrapper `setup onnx --enable` owns | `sudo voxtype setup onnx --enable` |
| The push-to-talk key vanished | The Omarchy binds are gated on `o.cmd_present("voxtype")` | Confirm `command -v voxtype`. On non-Omarchy systems you must bind `voxtype record start/stop` yourself. |

Debugging anything in the pipeline starts the same way — it is offline, writes
no history, and reads nothing real:

```bash
printf '%s' 'your test sentence here' | VOX_TRACE=1 VOX_NO_HISTORY=1 \
  VOX_MODE=sed+qwen ~/.local/bin/voxtype-punct
```

---

## Uninstall

This project reaches into six places. Backing it out by guesswork is hard, so
here is the whole list, in the order that leaves nothing running.

```bash
# 1. Take the plugin out of the bar and off the shell's registry.
#    `remove` handles a symlinked plugin correctly: it disables it, unlinks it
#    (your checkout is NOT deleted) and rescans. --yes skips the confirmation.
omarchy plugin remove local.voxtype --yes
#    Or by hand:
#      omarchy plugin disable local.voxtype
#      rm ~/.config/omarchy/plugins/local.voxtype      # rm, not rm -rf: it is a symlink
#      omarchy-shell shell rescanPlugins

# 2. Un-wire the post-processor. Delete the whole [output.post_process] table
#    from config.toml, then restart the daemon so it stops calling the wrapper.
$EDITOR ~/.config/voxtype/config.toml
systemctl --user restart voxtype

# 3. Remove the two binaries.
rm -f ~/.local/bin/voxtype-punct ~/.local/bin/hermes-voxtype-transcribe

# 4. Remove this project's config files. Everything else in that directory
#    belongs to voxtype itself, not to this repo.
rm -f ~/.config/voxtype/{polish-mode,polish-prompt.txt,polish-sed.sed,llm.conf}

# 5. Revoke and delete the credentials. Revoke the Gemini key in the AI Studio
#    console FIRST — deleting the local file does not invalidate it.
shred -u ~/.config/voxtype/gemini.key ~/.config/voxtype/llm.key 2>/dev/null

# 6. The backups ./install left behind, one per file it changed.
ls ~/.config/voxtype/*.bak.* ~/.local/bin/*.bak.* 2>/dev/null
#    They contain the same paths and secrets as the originals. Delete the ones
#    you no longer want, with shred for any that held a key.
```

Then delete your checkout, and if you no longer want the tools underneath:
`ollama rm vp-qwen7`, and `sudo pacman -Rns voxtype-bin`.

**One thing removal does not delete for you.** The dictation log survives all of
the above, because nothing in this list touches it and because deleting a record
of everything a person has said out loud should be a deliberate act:

```bash
ls -l ~/.local/state/voxtype/history.jsonl
shred -u ~/.local/state/voxtype/history.jsonl     # overwrite, then unlink
rmdir ~/.local/state/voxtype 2>/dev/null
```

`shred` is only meaningful on a conventional filesystem — on a copy-on-write
filesystem (btrfs, ZFS), on an SSD with wear levelling, or against an existing
backup or sync copy, overwriting one path does not reach the other copies. If
that matters to you, the answer is disk encryption, not this command. Also check
wherever your backups go.

---

## Repo layout

```
manifest.json          plugin manifest — must sit at the plugin root
Panel.qml              bar icon + pipeline editor (the bar-widget entry point)
Service.qml            watches and writes polish-mode
Model.js               spec parser / serializer  (must agree byte for byte
                       with the parser in bin/voxtype-punct)
History.qml            the SUPER+SHIFT+V window, and the voxtype-history
                       IPC target (open / close / toggle / copyLast)
HistoryModel.js        history.jsonl reader and filter
install                the installer described above — idempotent, --dry-run
bin/voxtype-punct      the post-process wrapper — the whole pipeline
bin/hermes-voxtype-transcribe
                       optional: batch-transcribe an audio file through the
                       same pipeline. Needs ffmpeg, python3 and a voxtype
                       build with the `transcribe` subcommand; finds the
                       wrapper on PATH or via $VOX_PUNCT, and always sets
                       VOX_NO_HISTORY=1 — a batch job is not dictation.
config/README.md       per-file copy instructions for everything below
config/config.toml.example       voxtype's own config, annotated
config/llm.conf.example          where the qwen stage sends your text
config/polish-prompt.txt         language-agnostic, shipped default
config/polish-prompt.pt-BR.txt   tuned pt-BR example
config/polish-sed.example.sed    neutral starter rules
config/polish-sed.pt-BR.sed      pt-BR rules, opt-in, do not enable for English
config/vp-qwen.Modelfile         FROM qwen2.5:7b + the shipped SYSTEM prompt
config/systemd/gpu.conf          optional NVIDIA/Vulkan drop-in
AGENTS.md              the install interview a coding agent runs for you
CLAUDE.md              points a coding agent at AGENTS.md
LICENSE                MIT
.gitignore             blocks gemini.key, history.jsonl, *.wav, model
                       weights, backups and docs/ — read the comments in it
                       before relaxing a rule
```

`docs/` is **gitignored and does not ship**. It holds the author's own session
notes; nothing in it is documentation for this project, and nothing outside it
depends on it.

One warning about the Modelfile: keep the `FROM qwen2.5:7b` version. Never
regenerate it with `ollama show --modelfile`, which emits
`FROM /var/lib/ollama/blobs/sha256-…` — a path that is meaningless on any other
machine, and unreadable besides, since `ollama.service` runs as `User=ollama`
with `ProtectHome=yes` and `OLLAMA_MODELS=/var/lib/ollama`. A registry name in
`FROM` sidesteps that entirely, which is why the shipped file uses one.

---

## License

MIT. voxtype is a separate project with its own license — see
[voxtype.io](https://voxtype.io).
