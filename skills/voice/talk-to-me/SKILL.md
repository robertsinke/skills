---
name: talk-to-me
description: Speak to the user out loud and listen for their spoken reply, using fully local, open-source text-to-speech (Piper) and speech-to-text (Vosk). Use when the user asks for voice mode, hands-free interaction, or explicitly asks the agent to talk instead of type.
---

# talk-to-me

Local, open-source voice I/O for an agent session. No account, no API key, no
cloud call - [Piper](https://github.com/OHF-Voice/piper1-gpl) (TTS, GPL-3.0) and
[Vosk](https://alphacephei.com/vosk) (STT, Apache-2.0) both run entirely on the
user's machine. This is deliberately not the browser's built-in Web Speech API:
that's free and zero-setup, but its recognition backend is typically a cloud
call to the browser vendor, not an open-source local engine.

## One-time setup

```sh
talk-to-me setup
```

Creates an isolated Python venv at `~/.agents/talk-to-me/venv` (does not touch
system/global Python), installs `vosk`, `piper-tts`, `sounddevice`, `numpy`
into it, and downloads a small default STT model + TTS voice (~100MB total,
one-time, cached in `~/.agents/talk-to-me/models`). The CLI script itself has
zero dependencies beyond python3 stdlib - only the isolated venv gets the ML
packages.

Check readiness any time with:

```sh
talk-to-me status
```

## Using it in a session

Speak to the user:

```sh
talk-to-me say "Here's what I found. Want me to go ahead?"
```

Listen for their reply. This records the mic, automatically stops about 1.2
seconds after the user stops talking (or after 30s max), and prints only the
transcript to stdout:

```sh
talk-to-me listen
```

A voice conversation is just alternating `say` / `listen` calls: read the
transcript `listen` printed, respond however you normally would, then `say`
the next line.

## When to use this

- The user explicitly asks for voice / talk mode, or says something like
  "let's talk this through" or "read that to me."
- Long-running or hands-free moments where the user is away from the keyboard.
- Don't switch to voice mode unprompted - ask first, it's a different
  interaction style than normal chat, and the user needs to know their mic is
  about to be recorded.

## Notes

- `listen` prints only the transcript to stdout. An empty line means it heard
  nothing - treat that as "no response," not an error.
- Default voice is Piper's `en_US-lessac-medium`. Swap voices by downloading a
  different Piper voice's `.onnx` + `.onnx.json` (browse
  [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices)) into
  `~/.agents/talk-to-me/models/` and setting `TALK_TO_ME_VOICE=<name>` before
  running `talk-to-me say`.
- Vosk's small model favors speed over accuracy. For noisy rooms or
  non-English speech, drop a bigger model from
  [alphacephei.com/vosk/models](https://alphacephei.com/vosk/models) into
  `~/.agents/talk-to-me/models/` and point `VOSK_MODEL_NAME` (edit the CLI
  script's default, or re-run with that model's folder name) at it.
- Everything happens locally: no text or audio leaves the machine.
- Linux users: if `sounddevice` fails to find an audio device, install
  `libportaudio2` (`apt install libportaudio2`); macOS wheels bundle it.
