# Claude Code Sandbox Devcontainer

A secure [dev container](https://containers.dev/) for running Claude Code in an isolated, network-restricted environment. The container uses iptables-based firewall rules to limit outbound network access to only the services Claude Code needs, preventing unintended or unauthorized network activity.

## What's Included

- **Node.js 20** (Debian Bookworm) base image
- **Claude Code** via the native installer
- **Zsh** with Powerlevel10k theme, fzf, and git integration
- **Development tools**: git, gh CLI, jq, vim, nano, git-delta
- **[Beads](https://github.com/steveyegge/beads)** (git-backed issue tracker) + Dolt
- **Network firewall** restricting outbound traffic to an allowlist

## Security Model

On container start, `init-firewall.sh` configures iptables to **drop all outbound traffic by default**, then selectively allows:

| Service | Purpose |
|---------|---------|
| `api.anthropic.com` | Claude API |
| `claude.ai` | Claude web services |
| GitHub (web, API, git IPs) | Git operations, `gh` CLI |
| `registry.npmjs.org` | npm package installs |
| `storage.googleapis.com` | Google Cloud storage |
| `sentry.io`, `statsig.com`, `statsig.anthropic.com` | Telemetry |
| VS Code marketplace / update domains | Extension installs |
| Docker host network | Host communication |
| DNS (UDP 53), SSH (TCP 22) | Infrastructure |

IPv6 is fully blocked. The firewall self-verifies by confirming `example.com` is unreachable and `api.github.com` + `api.anthropic.com` are reachable.

## Claude Code Permissions

The container ships with a `claude-settings.json` that pre-configures a sandbox permission model:

- **Allowed**: Common CLI tools (`npm`, `git`, `gh`, `node`, `grep`, `find`, etc.), file operations (`Read`, `Write`, `Edit`, `Glob`, `Grep`), and web access (`WebFetch`, `WebSearch`)
- **Denied**: Destructive commands (`rm -rf /`), privilege escalation (`sudo`), and pipe-to-shell patterns (`curl | bash`, `wget | bash`)

## Prerequisites

- [Docker](https://www.docker.com/) (or compatible runtime)
- A dev container-compatible editor ([VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers), or the [devcontainer CLI](https://github.com/devcontainers/cli))
- `ANTHROPIC_API_KEY` environment variable set on your host

## Quick Start

1. Clone this repository into your project (or copy the files):

   ```bash
   git clone https://github.com/youruser/devcontainer.git .devcontainer
   ```

2. Set your API key:

   ```bash
   export ANTHROPIC_API_KEY=sk-ant-...
   ```

3. Open the folder in VS Code and select **Reopen in Container**, or run:

   ```bash
   devcontainer up --workspace-folder .
   ```

4. Inside the container, Claude Code is ready:

   ```bash
   claude  # or use the alias: cc
   ```

## Configuration

### Build Arguments

Versions can be customized in `devcontainer.json` under `build.args`:

| Argument | Default | Description |
|----------|---------|-------------|
| `TZ` | `America/Los_Angeles` | Container timezone |
| `BEADS_VERSION` | `0.59.0` | Beads issue tracker version |
| `DOLT_VERSION` | `1.83.4` | Dolt database version |
| `GIT_DELTA_VERSION` | `0.18.2` | git-delta diff viewer version |
| `ZSH_IN_DOCKER_VERSION` | `1.2.0` | zsh-in-docker installer version |

### Volumes

Two named volumes persist data across container rebuilds:

- **`claude-code-bashhistory`** — Shell command history
- **`claude-code-config`** — Claude Code configuration (`~/.claude`)

### Extending the Allowlist

To allow additional domains, edit `init-firewall.sh` and add entries to either:

- `CDN_DOMAINS` — resolved with `/24` subnet masks (for CDN-backed services with rotating IPs)
- `STATIC_DOMAINS` — resolved to exact IPs

## Container Capabilities

The container requires `NET_ADMIN` and `NET_RAW` Linux capabilities (set via `runArgs`) to configure iptables firewall rules. These are only used by the `init-firewall.sh` script running as root via a scoped sudoers entry.

## License

See [LICENSE](LICENSE) for details.
