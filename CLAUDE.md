## gstack (recommended)

This project uses [gstack](https://github.com/garrytan/gstack) for AI-assisted workflows.
Install it for the best experience:

```bash
git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
cd ~/.claude/skills/gstack && ./setup --team
```

Skills like /qa, /ship, /review, /investigate, and /browse become available after install.
Use /browse for all web browsing. Use ~/.claude/skills/gstack/... for gstack file paths.

## What this folder is, and is not

This folder is the **Drones** game (a Godot tactical wargame set in early 2022). The user also opens sessions with this working directory
for topics that have nothing to do with it (so far: Symmetry, Climate change, Covid, Kill Zone, a Drones card game). Do not assume a
session started here is about the Drones game: take the topic from the user's first messages. For an unrelated topic, do not apply this
project's conventions (the doctrine log, the verification-and-commit workflow, the 2022 setting, knowledge locality, the headless test
suite) and do not draw on its memory. If a session is clearly a different subject, say once that a folder of its own would keep it apart
from this project's memory, instead of quietly treating everything as Drones.
