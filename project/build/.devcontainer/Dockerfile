FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Language stacks. new-dual-project sets these three defaults from its --with option; each one
# also needs its package hosts in allowed-domains.txt, which new-dual-project sets to match.

# R, plus the system libraries that common R packages build against (xml2/rvest, curl/httr,
# openssl). Packages install at run time from the CRAN mirror in allowed-domains.txt, which the
# root-owned Rprofile.site sets as the default.
ARG INSTALL_R=true
RUN if [ "$INSTALL_R" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
      r-base r-base-dev libcurl4-openssl-dev libssl-dev libxml2-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' >> /etc/R/Rprofile.site; \
  fi

# Python: the base image has Python 3; this adds pip, full venv support and headers for
# packages with C extensions. Packages install at run time from PyPI.
ARG INSTALL_PYTHON=false
RUN if [ "$INSTALL_PYTHON" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends python3-pip python3-venv python3-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*; \
  fi

# Web: the base image has Node.js and npm; this adds Playwright with headless Chromium. The
# browser has to be installed here, at build time, because the run-time firewall blocks the
# servers it downloads from. It's installed root-owned, so the agent can use it but not change
# it. Projects that use @playwright/test should pin the same version as PLAYWRIGHT_VERSION.
ARG INSTALL_WEB=false
ARG PLAYWRIGHT_VERSION=1.63.0
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN if [ "$INSTALL_WEB" = "true" ]; then \
    npm install -g playwright@${PLAYWRIGHT_VERSION} \
    && playwright install --with-deps chromium \
    && chmod -R a+rX /ms-playwright \
    && apt-get clean && rm -rf /var/lib/apt/lists/*; \
  fi
ENV NODE_PATH=/usr/local/lib/node_modules

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL=/bin/zsh

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

# Default powerline10k theme
ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Install Claude
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}


# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

# Root-owned, so the agent can't change them: the firewall's domain list, and managed settings
# whose deny rules hold even under --dangerously-skip-permissions
COPY allowed-domains.txt /usr/local/etc/allowed-domains.txt
COPY managed-settings.json /etc/claude-code/managed-settings.json
RUN chmod 0644 /usr/local/etc/allowed-domains.txt /etc/claude-code/managed-settings.json
USER node
