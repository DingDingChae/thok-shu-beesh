#!/usr/bin/env bash
set -euo pipefail

run_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true; then
    sudo "$@"
  else
    echo "dependency bootstrap needs non-interactive root access: $1" >&2
    exit 1
  fi
}

if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
  run_root apt-get update
  run_root apt-get install -y ca-certificates curl git docker.io
fi

install_deb() {
  local command_name="$1"
  local version="$2"
  local url="$3"
  local sha256="$4"
  if command -v "$command_name" >/dev/null 2>&1; then
    return
  fi
  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  curl --fail --location --silent --show-error "$url" --output "$work/package.deb"
  printf '%s  %s\n' "$sha256" "$work/package.deb" | sha256sum --check --status
  run_root dpkg -i "$work/package.deb" || {
    run_root apt-get install -f -y
    run_root dpkg -i "$work/package.deb"
  }
  rm -rf "$work"
  trap - RETURN
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "dependency bootstrap did not install $command_name $version" >&2
    exit 1
  }
}

install_deb pwsh 7.6.4 \
  'https://github.com/PowerShell/PowerShell/releases/download/v7.6.4/powershell_7.6.4-1.deb_amd64.deb' \
  'e5688e0569568d48051c49d3e93504cde47af709cdaaabd9a8892bc676b3bdf3'
install_deb gh 2.97.0 \
  'https://github.com/cli/cli/releases/download/v2.97.0/gh_2.97.0_linux_amd64.deb' \
  '7c7fa3bb890db0934baf65910d97b8c0fa437b2e590f7f7daf6bdf82c5c486d7'

run_root systemctl start docker 2>/dev/null || run_root service docker start
if ! docker info >/dev/null 2>&1; then
  if sudo -n docker info >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    printf '#!/usr/bin/env bash\nexec sudo -n /usr/bin/docker "$@"\n' > "$HOME/.local/bin/docker"
    chmod 0755 "$HOME/.local/bin/docker"
    printf '%s\n' "$HOME/.local/bin" >> "$GITHUB_PATH"
    export PATH="$HOME/.local/bin:$PATH"
  else
    echo 'Docker was installed but the current job cannot reach its daemon.' >&2
    exit 1
  fi
fi

git --version >/dev/null
gh --version >/dev/null
pwsh --version >/dev/null
docker version >/dev/null
