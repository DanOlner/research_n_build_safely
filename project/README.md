# PROJECT_NAME

A two-part Claude project, made from the dual-project template (version in `VERSION`).

- **`research/`**: on your machine, Claude searches and reads the web and any documents you put in `research/sources/`, and writes notes into `research/notes/`. It can't run commands, read outside its folder, or write outside `notes/`.
- **`build/`**: Claude works on the project inside a Docker container with permission checks skipped. It reads the notes at `/notes`, read-only. `build/` is the git repository you push.

`container.sh`, `check.py` and `pdf-text` stay in this top folder, outside `build/`, so the build agent can't change scripts you run on your machine.

The build container's language stacks are listed in `VERSION` (`stacks=`). See "Language stacks" below.

## First-time setup

1. **Trust the research folder.** Run `cd research && claude`, accept the trust dialog, then type `/exit`. Until you do, the research settings' allow rules are ignored.
2. **Container login** (once per machine). If `~/.config/claude-container/token.env` doesn't exist yet, run `claude setup-token`, then:
   ```
   mkdir -p -m 700 ~/.config/claude-container
   (umask 077; read -rsp 'Paste token: ' t; echo; printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n' "$t" > ~/.config/claude-container/token.env)
   ```
3. **Build the container image**: `./container.sh build`. The first build takes several minutes.
4. **Check everything**: `./check.py`. Every line should say PASS.

## Everyday use

**Research.** Start it from a terminal, not VS Code; the VS Code extension ignores this folder's permission mode.

```
cd research && claude
```

**Build.**

```
./container.sh claude
```

**Before leaving the build agent to run on its own**, commit your work in `build/` on your machine. Afterwards, check what the agent changed before you commit or run anything it wrote:

```
git -C build status --ignored
git -C build diff
```

The first lists every file and folder the agent added, changed or deleted. It also lists what `build/.gitignore` hides from a plain `git status`, such as `.venv/` and `node_modules/`, though not what changed inside them. The second shows the changes inside files you'd already committed. It doesn't show new files, so open those yourself. Pay most attention to:

- R scripts, `.Rprofile`, `.Renviron` and `.RData`
- Python scripts, `setup.py` and `pyproject.toml`
- `package.json`, especially its `scripts`
- `.gitignore` and `.gitattributes` files, which change what these two commands show
- anything under `.github/`

To run one of its R scripts on your machine, use `Rscript --vanilla script.R`, which skips the project's R startup files. Keep Python and npm dependencies in the container: installing them on your machine runs code from those packages, and the agent can change anything in its own `.venv` and `node_modules`, so don't use those on your machine either.

To throw away everything the agent did since your last commit, including ignored files such as `.venv/` and any git repositories it created inside `build/`:

```
git -C build reset --hard && git -C build clean -ffdx
```

Push from your machine as usual.

## Working with PDFs

Copy PDFs into `research/sources/` (subfolders are fine), then make text copies of the new ones:

```
./pdf-text
```

It writes `report.txt` next to each new or changed `report.pdf`, starting each page with a `--- PDF page N ---` line so Claude can cite pages. Research sessions search and read the text copies, which is exact and cheap. They open a PDF itself for charts, tables the copy garbles, and scanned pages, which have no text to copy. `./pdf-text` says how many pages in each document have little or no text. To redo a copy, delete the `.txt` and run it again.

`./pdf-text` and Claude's own PDF reading both need poppler-utils, once per machine: `sudo apt install poppler-utils`.

`sources/` stays on the research side: the build container sees only `notes/`. Claude can't write in `sources/`, so what it learns from the documents goes into `notes/`.

**Confidential documents.** A PDF can hide instructions, as a web page can, and research sessions can fetch any website. For confidential documents, start research without web tools, so a session has no tool for sending their contents to a website:

```
cd research && claude --disallowedTools WebFetch WebSearch
```

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

**Viewing a dev server in your own browser** is off by default. To turn it on, set `PUBLISH_PORTS="5173"` at the top of `container.sh`, start the dev server with `--host 0.0.0.0`, then run `./container.sh stop` and `start`. The port is reachable only from your machine. But opening pages the agent wrote in your own browser runs its code on your machine, outside the container's firewall. Review the code first, or use a separate browser profile.

**Adding a stack later:** in `build/.devcontainer/`, set its `ARG INSTALL_...=true` line in `Dockerfile` and uncomment its lines in `allowed-domains.txt`. Then run `./container.sh rebuild` and add it to `stacks=` in `VERSION`.

## After Claude Code updates

Run `./check.py`. Claude Code updates itself on your machine. The container's copy is fixed when the image is built; `./container.sh rebuild` updates it.

## What isn't covered

- DNS lookups from the container aren't filtered.
- The container's login token is visible to the agent. It can only reach the Anthropic API and the allowed domains, and it can only make model requests.
- Research fetches can reach any website.
- Opening `build/` with VS Code's Dev Containers extension uses `build/.devcontainer/devcontainer.json`. It mirrors `container.sh` but hasn't been tested, and may need the VS Code hosts uncommented in `allowed-domains.txt`.
