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

Each stack installs its tools in the image and opens the firewall to its package hosts, and nothing else. Then follow "First-time setup" in the new project's `README.md`. To work on an existing project on another machine, clone its repository and follow "Cloning onto another machine" in its `README.md` instead.

`--convos` also keeps research's and the build agent's conversations as readable Markdown, in `llm_convos/research/` and `llm_convos/build/`, using the [export_all_convos](https://github.com/DanOlner/export_all_convos) scripts. They're converted automatically: research's when a research session ends, and the build agent's when `./container.sh claude` exits. Each folder's `.gitignore` keeps its conversations out of git until you allow them one at a time. "Conversation records" in the new project's `README.md` has the rest.

`--pages` publishes `build/docs/` as the repository's GitHub Pages site. Pages' simple *Deploy from a branch* setting can serve only the repository root or a top-level `/docs` folder, so a workflow at the top of the repository, `.github/workflows/publish-docs.yml`, publishes `build/docs` exactly as committed whenever a push changes it. It runs none of the project's code, sits where the build agent can't change it, and refuses symbolic links in `build/docs`, which the upload would follow. The build agent is told that `docs/` is the published site. "Publishing build/docs with GitHub Pages" in the new project's `README.md` has the one-time setting on GitHub.

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
  commit-check       git pre-commit hook: refuses commits that add an Anthropic token or API key
  convos             with --convos: converts research's and the build agent's conversations (run by hooks)
  scripts/           with --convos: the export_all_convos scripts
  llm_convos/        with --convos: not visible to either agent
    research/        research's conversations as Markdown; its .gitignore keeps them out of git until allowed
    build/           the build agent's, the same way
  .github/workflows/publish-docs.yml   with --pages: publishes build/docs/ to GitHub Pages
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

Your repository:

- A git pre-commit hook refuses commits that add an Anthropic token or API key, such as the container's login token if the agent wrote it into a file. It catches only a credential written out in full.
- With `--convos`, the same hook refuses a conversation that its folder's `.gitignore` doesn't allow, and an allowed one that export_all_convos's scan finds a credential in, of any kind the scan knows.
- With `--pages`, the workflow that publishes `build/docs/` is outside `build/`, so the agent can't change what runs on GitHub with permission to publish. It runs none of the project's code, refuses symbolic links in `build/docs/`, doesn't keep its checkout's credentials, and pins its actions to commits. What's in `build/docs/` becomes a public website when you push it, so it's yours to review first.

Claude Code trusts a whole git repository at once, so trusting a project covers `build/`. Never start Claude Code on your machine inside `build/`.

## Why two parts

Most setups run one sandboxed agent that does everything, web research included. Anthropic's reference devcontainer and Trail of Bits' [claude-code-devcontainer](https://github.com/trailofbits/claude-code-devcontainer) both work that way. This template instead follows the advice to [split the work](https://martinfowler.com/articles/agentic-ai-security.html) so that no agent has the whole [lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/): private data, untrusted content, and a way to send data out. When this was checked in October 2026, no ready-made setup combined the two.

- Research reads the web but can't run commands.
- The build agent runs commands but has no web tools, can reach only the Anthropic API and package hosts, and has a login that only covers model requests.
- Findings reach the build agent only through `notes/`, which you can read first.

There are two costs. The build agent can't look things up mid-task, so research has to anticipate what it needs. And research is restricted by Claude Code's permission rules rather than by OS isolation, which is why its checks rerun after every update.

## Updating the template

Projects are copies, so changes here don't reach existing projects. Each project's `VERSION` says which template version it came from.

After changing anything in `project/`, `project-convos/` or `project-pages/`, create a throwaway project with `--convos --pages`, run its `./check.py`, and raise `template_version` in `project/VERSION`.

`project-convos/` holds what `--convos` adds to a project. `new-dual-project` also adds a `SessionEnd` hook to research's settings, and keeps the README's "Conversation records" section, which sits between `<!-- convos -->` lines in `project/README.md`; without `--convos` it removes that section.

`project-pages/` holds the workflow `--pages` adds. `new-dual-project` sets its `branches:` to the branch `git init` creates, and keeps the sections between `<!-- pages -->` lines in `project/README.md` and `project/build/CLAUDE.md`; without `--pages` it removes them. After changing the workflow, lint it with [actionlint](https://github.com/rhysd/actionlint), which can run in a throwaway container: `docker run --rm --network none -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:latest`, in the folder above `.github`.

## Where the files came from

- **Container files:** Anthropic's reference devcontainer (`anthropics/claude-code`, `.devcontainer/`). The firewall changes are listed at the top of `init-firewall.sh`. Additions: the R, Python and web stacks, the domain list, managed settings, read-only mounts and resource limits.
- **Research settings:** the hardened profile from testing.
- **Conversation export scripts:** `project-convos/scripts/` is the `scripts/` folder of [export_all_convos](https://github.com/DanOlner/export_all_convos) at commit `3674d6d`, unchanged, and each `llm_convos/<side>/.gitignore` starts as its deny-all stub. To update them, copy a newer `scripts/` folder over it. `convos` uses `find_convo_dir` and `export_all_convos.py`'s `--convo-dir`, `--output-dir` and `--redact`, and `publish_convos.py`'s `read_entries` and `git_tracked`, so check those still exist.
- **GitHub Pages workflow:** first written by the build agent in `~/claude/projects/modelling_firm_demand`, then reviewed and tightened: its actions pinned to commits (checkout v7.0.1, configure-pages v6.0.0, upload-pages-artifact v5.0.0 and deploy-pages v5.0.1, the latest in October 2026), the checkout's credentials not kept, the symbolic-link check added, and the branch set when the project is created.
