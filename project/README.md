# PROJECT_NAME

A two-part Claude project, made from the dual-project template (version in `VERSION`).

- **`research/`**: on your machine, Claude searches and reads the web and any documents you put in `research/sources/`, and writes notes into `research/notes/`. It can't run commands, read outside its folder, or write outside `notes/`.
- **`build/`**: Claude works on the project inside a Docker container with permission checks skipped. It reads the notes at `/notes`, read-only.

This whole folder is one git repository, which you push: research notes, build code and these scripts, but not the documents in `research/sources/`. The build container never sees the repository. Once the container has run, empty `build/.git` and `build/.claude` folders owned by root appear. They're placeholders that stop the agent creating a repository or Claude Code settings there, and git ignores them.

`container.sh`, `check.py`, `pdf-text`, `research-gate` and `commit-check` stay in this top folder, outside `build/`, so the build agent can't change scripts you run on your machine.
<!-- convos -->
So do `convos` and `scripts/`, which keep the conversation records (see "Conversation records").
<!-- /convos -->
<!-- pages -->
`.github/workflows/publish-docs.yml`, which publishes `build/docs/`, is up here too, out of the agent's reach (see "Publishing build/docs with GitHub Pages").
<!-- /pages -->

The build container's language stacks are listed in `VERSION` (`stacks=`). See "Language stacks" below.

## First-time setup

1. **Trust the project.** Run `cd research && claude`, accept the trust dialog, then type `/exit`. Until you do, the research settings' allow rules are ignored. Claude Code trusts a whole git repository at once, so this covers the project folder, `build/` included. That's why you should never start Claude Code on your machine inside `build/` (see "What isn't covered").
2. **Container login** (once per machine). If `~/.config/claude-container/token.env` doesn't exist yet, run `claude setup-token`, then:
   ```
   mkdir -p -m 700 ~/.config/claude-container
   (umask 077; read -rsp 'Paste token: ' t; echo; printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$t" > ~/.config/claude-container/token.env)
   ```
3. **Build the container image**: `./container.sh build`. The first build takes several minutes.
4. **Check everything**: `./check.py`. Every line should say PASS.
5. **Make the first commit**: `git add -A && git commit -m "New project"`. It's your restore point before the build agent runs.

## Everyday use

**Research.** Start it from a terminal, not VS Code; the VS Code extension ignores this folder's permission mode.

```
cd research && claude
```

**Build.**

```
./container.sh claude
```

**Before leaving the build agent to run on its own**, commit your work: `git add -A && git commit`. Afterwards, check what changed before you commit or run anything the agent wrote. In this folder, run:

```
git status --ignored
git diff
```

The first lists every file and folder that was added, changed or deleted: by the build agent in `build/`, and by research in `research/notes/`. It also lists what the `.gitignore` files hide from a plain `git status`, such as `.venv/`, `node_modules/` and the documents in `research/sources/`, though not what changed inside them. The second shows the changes inside files you'd already committed. It doesn't show new files, so open those yourself. Pay most attention to:

- R scripts, `.Rprofile`, `.Renviron` and `.RData`
- Python scripts, `setup.py` and `pyproject.toml`
- `package.json`, especially its `scripts`
- `.gitignore` and `.gitattributes` files, which change what these two commands show
- anything under `.github/`

To run one of its R scripts on your machine, use `Rscript --vanilla script.R`, which skips the project's R startup files. Keep Python and npm dependencies in the container: installing them on your machine runs code from those packages, and the agent can change anything in its own `.venv` and `node_modules`, so don't use those on your machine either.

To throw away everything the build agent did since your last commit, including ignored files such as `.venv/` and any git repositories it created inside `build/`, while leaving research alone:

```
git restore --source=HEAD --staged --worktree -- build && git clean -ffdx -- build
```

Keep the `-- build` on both. `git reset --hard` would also throw away uncommitted research notes, and `git clean -ffdx` without `-- build` would delete your PDFs in `research/sources/`.

**Tokens in commits.** A git hook, `commit-check`, refuses any commit that would add an Anthropic credential: the container's login token or an API key, which both start `sk-ant-`. It names the files and leaves fixing them to you. It only catches a credential written out in full, so an encoded copy gets past it, and it doesn't replace checking what changed. For a false alarm, `git commit --no-verify` skips it. Git doesn't copy hooks into clones, so a clone needs it linked again (see "Cloning onto another machine"). `./check.py` says if the hook is missing.

Push from your machine as usual.

<!-- pages -->
## Publishing build/docs with GitHub Pages

This project publishes `build/docs/` as its GitHub Pages site, at `https://<owner>.github.io/<repository>/` once it's set up. The build agent is told that `docs/` is the published site.

GitHub Pages' simple *Deploy from a branch* setting can serve only the repository root or a top-level `/docs` folder, so it can't point at `build/docs`. Instead, the workflow `.github/workflows/publish-docs.yml` publishes `build/docs` exactly as committed whenever a push changes it. It builds nothing and runs none of the project's code, so the site is built in the container and committed. It sits outside `build/`, so the agent can't change what runs on GitHub. It stops without publishing if `build/docs/index.html` is missing, or if `build/docs` contains symbolic links, which the upload would follow to files elsewhere in the repository.

**Setting it up (once):** push the repository to GitHub, then in its settings, under *Pages*, set *Source* to *GitHub Actions*. Test it by running *Publish to GitHub Pages* by hand from the *Actions* tab.

**Updating the site:** ask the build agent to rebuild it into `build/docs/`, or build it yourself inside the container (`./container.sh shell`), not on your machine. Then review `build/docs`, commit it and push.

**The workflow** publishes from the branch `git init` created with the project. If you rename the branch, change `branches:` in the workflow to match. Its actions are pinned to commits, so a tag moved later can't change what runs with permission to publish. To update one, replace its commit and version comment with a newer release's; `git ls-remote https://github.com/actions/checkout refs/tags/v7.0.1`, for example, prints a release's commit.

The pages are the build agent's code, and they run in the browser of everyone who visits the site, so review changes to `build/docs` before you push them, as you would anything you publish. On most GitHub plans, a Pages site is public even when its repository is private.

<!-- /pages -->
## Cloning onto another machine

Cloning this repository gives you the notes, the build code and these scripts. Nothing in the project depends on where it lives, so the clone can go in any folder, and it doesn't need the template. If you can, use a folder with the same name: the container and image names come from it.

**Once per machine:**

- Install Claude Code, and poppler-utils for PDFs (`sudo apt install poppler-utils`).
- Make Docker usable without `sudo`: `sudo usermod -aG docker $USER`, then log out of your desktop session and back in.
- Save a container login token, as in step 2 of "First-time setup". Make a new one on each machine rather than copying one across, and never put it in the repository.

**Then, in the clone's top folder:**

1. **Link the commit hook:** `ln -s ../../commit-check .git/hooks/pre-commit`. Git doesn't copy hooks into clones.
2. **Trust the project:** `cd research && claude`, accept the trust dialog, then type `/exit`. Each machine keeps its own list of trusted folders.
3. **Build the container image:** `./container.sh build`. Images aren't in the repository.
4. **Run `./check.py` yourself.** Every line should say PASS. Don't leave this to the automatic checks: they only run when Claude Code's version differs from the one in `VERSION`, and `VERSION` comes with the clone. On a machine with the same version, they would count the other machine's pass and not run, and miss anything particular to this machine, such as its own Claude Code settings.

**What the clone doesn't have:**

- **The documents in `research/sources/`.** Git ignores them. Copy them across yourself, then run `./pdf-text`.
- **Conversation history.** Research sessions are kept in `~/.claude/projects/` and the build agent's in a Docker volume, both on the machine where they happened. `claude --continue` and `./container.sh claude --continue` start fresh on a new machine. The notes and the two `CLAUDE.md` files are what carry across.
- **What `build/.gitignore` leaves out**, such as `.venv/` and `node_modules/`, plus anything the build agent has added there, like generated results. Reinstall or regenerate it inside the container. Read `build/.gitignore` before you push, so you know what won't come across.

**Working from two machines:** `./check.py --accept` and the automatic checks write to `VERSION`, so pulling can bring a conflict there. Keep the lines from the machine with the newer Claude Code version.

## Working with PDFs

Copy PDFs into `research/sources/` (subfolders are fine), then make text copies of the new ones:

```
./pdf-text
```

It writes `report.txt` next to each new or changed `report.pdf`, starting each page with a `--- PDF page N ---` line so Claude can cite pages. Research sessions search and read the text copies, which is exact and cheap. They open a PDF itself for charts, tables the copy garbles, and scanned pages, which have no text to copy. `./pdf-text` says how many pages in each document have little or no text. To redo a copy, delete the `.txt` and run it again.

`./pdf-text` and Claude's own PDF reading both need poppler-utils, once per machine: `sudo apt install poppler-utils`.

`sources/` stays on the research side: the build container sees only `notes/`. Git ignores it too, since journal articles are usually copyrighted and PDFs soon get too big for a repository. Claude can't write in `sources/`, so what it learns from the documents goes into `notes/`, which is committed.

**Confidential documents.** A PDF can hide instructions, as a web page can, and research sessions can fetch any website. For confidential documents, start research without web tools, so a session has no tool for sending their contents to a website:

```
cd research && claude --disallowedTools WebFetch WebSearch
```

<!-- convos -->
## Conversation records

Research's and the build agent's conversations are kept as readable Markdown, by the [export_all_convos](https://github.com/DanOlner/export_all_convos) scripts in `scripts/`, in a folder for each:

- **`llm_convos/research/`**: converted in the background each time a research session ends.
- **`llm_convos/build/`**: converted each time `./container.sh claude` exits. The build agent can change anything in its Claude volume, so only its transcripts are copied out, under names `convos` checks first.

To convert them yourself, run `./convos`, or `./convos research` or `./convos build` for one side. Each run converts every conversation again, so ones that carried on are brought up to date, and prints a line for each side. The full output of the last run is in each folder's `.export.log`.

**Nothing is committed until you allow it.** Each folder's `.gitignore` ignores everything in it, and lists every conversation, commented out, with what a scan for credentials and personal information found:

```
# --- [clean] 2026-10-12_1105_Find_the_latest_ONS_business_survey.md
# !2026-10-12_1105_Find_the_latest_ONS_business_survey.md
```

To publish one, read it, then delete the `# ` in front of its `!` line. Put the `# ` back to withdraw it. Your choices are kept each time the list is regenerated, except that a conversation whose scan result gets worse is withdrawn, so you decide again. `scripts/README.md` has the details, including `publish_convos.py` for doing this from the command line (give it `--dir llm_convos/research` or `--dir llm_convos/build`).

`commit-check` refuses a commit that adds a conversation the staged `.gitignore` doesn't allow, or an allowed one the scan finds a credential in. Git keeps tracking a conversation once it's committed, whatever `.gitignore` says, so this is what keeps a withdrawn conversation's new content out: allow it again, or take it out of git with `git rm --cached`.

Before you allow a conversation:

- **Read it.** Research's conversations quote the documents in `research/sources/`, which git otherwise keeps out. The build agent's are its own words, so weigh them as you would its code.
- **The list itself is committed**, so the names of all the conversations, made from the first words of each, are in the repository even when the conversations aren't.
- **Don't edit an exported file**: the next run overwrites it. To publish a shortened version, copy it to a new name in the same folder, edit the copy and allow that.
- **Your home folder is in every path** in research's conversations. To have it replaced with `~`, set `REDACT = True` near the top of `convos`. Running `scripts/redact_convos.py` afterwards doesn't last, because the next run converts everything again.

Only research and build conversations are kept, not sessions you start elsewhere, such as in this top folder. Ones you start from `./container.sh shell` are converted the next time `./container.sh claude` exits or you run `./convos`. A clone has the conversations you allowed; the rest stay on the machine they were made on. Use `./convos` rather than `scripts/export_all_convos.py`, which, run from here, would look for this top folder's conversations instead. Its `--install-hook` isn't needed either: `commit-check` does that job.

<!-- /convos -->
## Changing what the container can reach

Edit `build/.devcontainer/allowed-domains.txt` (one domain per line), then run `./container.sh rebuild`. Each domain you add is somewhere the container can reach, along with its login token, so add only what the build needs.

If package installs start failing after the container has been running a long time, `./container.sh firewall` refreshes the allowed sites' addresses.

Resource limits (4 CPUs, 8 GB of memory, 1,024 processes, 1 GB of shared memory for the browser) are at the top of `container.sh`.

## Language stacks

Chosen when the project was created (`new-dual-project --with r,python,web`). Each stack installs its tools in the image and opens the firewall to its package hosts, and nothing else.

| Stack | In the image | Firewall opens |
|---|---|---|
| `r` | R, with CRAN as the default repository | `cloud.r-project.org` |
| `python` | pip, `venv` and headers for C extensions (Python 3 is always there) | `pypi.org`, `files.pythonhosted.org` |
| `web` | Playwright with headless Chromium (Node.js and npm are always there) | `registry.npmjs.org` |

**Python:** create a virtual environment in the project (`python3 -m venv .venv`) and install into that.

**Web:** run the dev server inside the container, for example on `localhost:5173`. Headless Chromium in the same container can load it, and Claude tests by writing and running Playwright scripts and looking at their screenshots. The browser is built into the image at Playwright version 1.63.0. If the project uses `@playwright/test`, pin it to the same version (`npm install -D @playwright/test@1.63.0`): any other version would try to download a browser, and the firewall blocks that. Pages that load fonts or scripts from outside CDNs will fail unless those CDNs are added to `allowed-domains.txt`.

The npm registry also accepts package publishing from anyone holding an account's credentials, which is why only web projects open it.

**Viewing a dev server in your own browser** is off by default. To turn it on, put the ports in the `PUBLISH_PORTS` line near the top of `container.sh`, for example `PUBLISH_PORTS="${PUBLISH_PORTS-8000 8001}"`. Then run `./container.sh stop` and `./container.sh claude --continue`. The agent sees the list as `$PUBLISH_PORTS`, and is told to serve on `0.0.0.0` on one of those ports, so you open `http://localhost:8000`. The ports are reachable only from your machine. But opening pages the agent wrote in your own browser runs its code on your machine, outside the container's firewall. Review the code first, or use a separate browser profile.

**Adding a stack later:** in `build/.devcontainer/`, set its `ARG INSTALL_...=true` line in `Dockerfile` and uncomment its lines in `allowed-domains.txt`. Then run `./container.sh rebuild` and add it to `stacks=` in `VERSION`.

## After Claude Code updates

The safety checks run by themselves when Claude Code's version changes, and each side refuses to run on a version that hasn't passed them:

- **Research:** when a research session starts on a new version, `research-gate` runs the research checks first. That adds about 10 seconds, once per update, plus a little of your usage, and a one-line message says why. If they pass, the version is recorded and research carries on. If a check fails, or research has gained a tool it didn't have before, research is paused, and every prompt is refused until `./check.py --research-only --accept` passes.
- **Container:** its Claude Code only changes when you rebuild. `./container.sh rebuild` installs the version your machine has, then restarts the container. `build`, `rebuild` and `claude` run the container checks when the image has a version that hasn't passed them, taking about 20 seconds. If the checks fail, Claude isn't started in the container.

`VERSION` records what passed: `tested_research`, `tested_container` and research's accepted tool list. To check by hand, run `./check.py`. Add `--accept` to record the result, once you've read any warnings.

## What isn't covered

- Claude Code sessions on your machine. Never start one inside `build/` or its subfolders: the trust you gave the project covers them, and the agent can write Claude Code settings in subfolders, including hooks that run commands. A session started elsewhere that reads files in `build/` also reads the agent's `build/CLAUDE.md`, so weigh its suggestions as you would the agent's code.
- DNS lookups from the container aren't filtered.
- The container's login token is visible to the agent. It can only reach the Anthropic API and the allowed domains, and it can only make model requests. `commit-check` stops it being committed as plain text, but not encoded.
- Research fetches can reach any website.
- Opening `build/` with VS Code's Dev Containers extension uses `build/.devcontainer/devcontainer.json`. It mirrors `container.sh` but hasn't been tested, and may need the VS Code hosts uncommented in `allowed-domains.txt`.
- Machines other than Linux. The scripts and the container's firewall have only been tested on Linux.
