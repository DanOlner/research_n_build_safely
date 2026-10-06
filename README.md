# dual-project template

Creates two-part Claude projects: web research on your machine, and building inside a locked-down container where Claude runs with permission checks skipped. It packages the configuration that passed testing in `~/claude/testfolder`; the full results are in `results/results.md` there.

## Create a project

```
new-dual-project --with r,python,web ~/claude/projects/my-project
```

`--with` picks the build container's language stacks. It defaults to `r`.

- **`r`:** R, with packages from CRAN.
- **`python`:** pip and `venv`, with packages from PyPI.
- **`web`:** Playwright with headless Chromium for testing pages served inside the container, with packages from the npm registry.

Each stack installs its tools in the image and opens the firewall to its package hosts, and nothing else. Then follow "First-time setup" in the new project's `README.md`.

## What a project contains

```
my-project/          one git repository: what you commit and push
  README.md          everyday use
  VERSION            template version, and the Claude Code versions that passed the checks
  .gitignore         keeps the documents in research/sources/ out of git
  container.sh       start, use and stop the build container
  check.py           the safety checks: run after setup; they rerun by themselves after updates
  pdf-text           text copies of the PDFs in research/sources/
  research-gate      reruns the research checks after Claude Code updates (called by research's hooks)
  research/
    .claude/settings.json   the research profile: no shell, writes only to notes/, no skip-permissions
    CLAUDE.md
    sources/         PDFs you add, and their text copies; not in git, not visible to the container
    notes/           mounted read-only into the container at /notes
  build/             the build agent's workspace, mounted into the container at /workspace
    CLAUDE.md
    .gitignore       installed packages, caches and test reports
    .devcontainer/   image, firewall, domain list, managed settings (read-only inside the container)
    .vscode/         read-only inside the container
```

## What's enforced

Research side:

- No shell or subagent tools. Your claude.ai connectors (Gmail, Drive and so on) aren't loaded, and connector tools are denied as a second layer.
- Reads limited to the folder; writes only to `notes/`.
- Starts in `dontAsk` mode, and refuses skip-permissions and auto mode.
- No git status snapshot in its sessions, so it never sees the names of files the build agent creates.
- After a Claude Code update, the research checks run once when a session starts, and research is paused if they fail.

Build container:

- Reaches only the Anthropic API and the domains in `allowed-domains.txt`: the package hosts for the project's stacks.
- No web tools, enforced by root-owned managed settings.
- `/notes`, `.devcontainer` and `.vscode` are read-only.
- No git repository: the project's repository stays on the host. `/workspace/.git` and `/workspace/.claude` are empty read-only placeholders, so the agent can't create a repository, or Claude Code settings with hooks, where host tools would pick them up.
- No access to your home folder or to Docker.
- CPU, memory and process limits.
- When the image gets a new Claude Code version, the container checks run before Claude starts in it.

Claude Code trusts a whole git repository at once, so trusting a project covers `build/`. Never start Claude Code on your machine inside `build/`.

## Why two parts

Most setups run one sandboxed agent that does everything, web research included. Anthropic's reference devcontainer and Trail of Bits' [claude-code-devcontainer](https://github.com/trailofbits/claude-code-devcontainer) both work that way. This template instead follows the advice to [split the work](https://martinfowler.com/articles/agentic-ai-security.html) so that no agent has the whole [lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/): private data, untrusted content, and a way to send data out. When this was checked in October 2026, no ready-made setup combined the two.

- Research reads the web but can't run commands.
- The build agent runs commands but has no web tools, can reach only the Anthropic API and package hosts, and has a login that only covers model requests.
- Findings reach the build agent only through `notes/`, which you can read first.

There are two costs. The build agent can't look things up mid-task, so research has to anticipate what it needs. And research is restricted by Claude Code's permission rules rather than by OS isolation, which is why its checks rerun after every update.

## Updating the template

Projects are copies, so changes here don't reach existing projects. Each project's `VERSION` says which template version it came from.

After changing anything in `project/`, create a throwaway project, run its `./check.py`, and raise `template_version` in `project/VERSION`.

## Where the files came from

- **Container files:** Anthropic's reference devcontainer (`anthropics/claude-code`, `.devcontainer/`). The firewall changes are listed at the top of `init-firewall.sh`. Additions: the R, Python and web stacks, the domain list, managed settings, read-only mounts and resource limits.
- **Research settings:** the hardened profile from testing.
