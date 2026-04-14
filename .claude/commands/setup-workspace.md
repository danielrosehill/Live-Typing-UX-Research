---
description: First-run setup — name this workspace, seed context, and replace template placeholders.
---

# /setup-workspace

Run this once, immediately after cloning the template.

## Steps

### 1. Ask the user (one batched AskUserQuestion)

- **Project name** — short, human-readable (e.g. "Linux Audio Notes", "Kubernetes How-To Vault").
- **One-line description** — what kinds of technical questions will live here?
- **Primary stack/domain** — free text (e.g. "Ubuntu desktop, KDE, PipeWire", "Next.js + Vercel + Cloudflare").
- **Visibility intent** — public (default) or private. Used only to set tone in `context/`; doesn't change the repo.

### 2. Replace placeholders

In both `CLAUDE.md` and `README.md`, replace:

- `{{PROJECT_NAME}}` → the project name
- `{{DESCRIPTION}}` → the one-line description

### 3. Seed `context/`

Create `context/stack.md` with the user's stack/domain answer. Add a short note at the top:

> This file is read by every command. Keep it accurate — outdated context produces outdated ideas.

### 4. Initialise the topics index

Ensure the top-level `README.md` contains a "Topics" section. If empty, leave the placeholder in place:

```markdown
## Topics

_No topics yet — run `/ask` to add one._
```

`/publish` will rebuild this section into a two-column table once topics exist.

### 5. Commit

```bash
git add -A
git commit -m "Initialise workspace: <project name>"
git push
```

### 6. Report

Tell the user the workspace is ready and suggest `/ask` as the next step.
