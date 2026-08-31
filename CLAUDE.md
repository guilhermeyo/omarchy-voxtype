# CLAUDE.md

The setup instructions for this repo live in **[`AGENTS.md`](AGENTS.md)** — read
that file and follow it.

It is the script for installing this project on someone's machine: which
questions to ask them first (where the language model runs, what language they
dictate in, whether they are on Omarchy, where their API key goes), what to
install, how to verify it, and what to tell them about privacy before you finish.

This is a real file rather than a symlink to `AGENTS.md` on purpose:
`omarchy plugin validate` rejects any symlink inside a plugin folder, and this
repo is checked out directly as an Omarchy shell plugin.
