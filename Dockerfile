FROM node:20-bookworm

ARG TZ
ENV TZ="$TZ"

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  wget \
  curl \
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

ARG BEADS_VERSION=0.59.0
ARG DOLT_VERSION=1.83.4
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install Dolt (required by beads)
RUN ARCH=$(dpkg --print-architecture) && \
  if [ "$ARCH" = "amd64" ]; then DOLT_ARCH="amd64"; else DOLT_ARCH="arm64"; fi && \
  wget "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-${DOLT_ARCH}.tar.gz" && \
  tar -xzf "dolt-linux-${DOLT_ARCH}.tar.gz" && \
  sudo cp dolt-linux-${DOLT_ARCH}/bin/dolt /usr/local/bin/ && \
  rm -rf "dolt-linux-${DOLT_ARCH}.tar.gz" dolt-linux-${DOLT_ARCH}

# Install Beads (git-backed issue tracker for AI agents)
RUN ARCH=$(dpkg --print-architecture) && \
  if [ "$ARCH" = "amd64" ]; then BEADS_ARCH="amd64"; else BEADS_ARCH="arm64"; fi && \
  wget -q "https://github.com/steveyegge/beads/releases/download/v${BEADS_VERSION}/beads_${BEADS_VERSION}_linux_${BEADS_ARCH}.tar.gz" -O /tmp/beads.tar.gz && \
  cd /tmp && tar -xzf beads.tar.gz && \
  cp /tmp/bd /usr/local/bin/bd && \
  chmod +x /usr/local/bin/bd && \
  rm -rf /tmp/beads.tar.gz /tmp/bd /tmp/CHANGELOG.md /tmp/LICENSE /tmp/README.md && \
  bd --version

# Enable corepack and install pnpm (must run as root to symlink into /usr/local/bin)
RUN corepack enable && corepack prepare pnpm@latest --activate

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/home/node/.local/bin:$PATH:/usr/local/share/npm-global/bin

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

# Install Claude Code (native installer, replaces deprecated npm package)
RUN curl -fsSL https://claude.ai/install.sh | bash \
  && echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc \
  && echo 'alias cc="claude"' >> ~/.zshrc \
  && echo 'alias ccd="claude --dangerously-skip-permissions"' >> ~/.zshrc

# Copy default Claude Code settings and commands to a stable location (the .claude dir gets masked by volume mount)
COPY claude-settings.json /usr/local/share/claude-settings-default.json
COPY claude-state.json /usr/local/share/claude-state-default.json
COPY commands/ /usr/local/share/claude-commands-default/

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  chmod 644 /usr/local/share/claude-settings-default.json && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD claude --version || exit 1
