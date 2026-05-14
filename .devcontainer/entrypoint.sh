#!/usr/bin/env bash
# Claude Code Sandbox entrypoint. The container is single-use: this runs
# at startup, then execs sshd. All configuration is driven by env vars.
#
# Environment variables (all optional):
#   SSH_PUBLIC_KEY        Public key installed in ~claude/.ssh/authorized_keys.
#   SSH_GITHUB_KEYS_USER  GitHub username; their public keys are fetched
#                         from https://github.com/<user>.keys and appended.
#   AI_CONTEXT_REPO       Git URL cloned into $AI_CONTEXT_DIR on first
#                         start. Runs before the firewall is applied, so
#                         it has full outbound network access. Must be
#                         reachable without an interactive credential
#                         prompt (public URL or URL with embedded token).
#   AI_CONTEXT_DIR        Parent directory for the AI_CONTEXT_REPO clone.
#                         Default: /home/claude/ai-context.

set -u

APP_USER="claude"
APP_HOME="/home/${APP_USER}"
SSH_DIR="${APP_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

# ---- SSH authorized_keys ---------------------------------------------------
install -d -m 700 -o "${APP_USER}" -g "${APP_USER}" "${SSH_DIR}"
: > "${AUTH_KEYS}"

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  printf '%s\n' "${SSH_PUBLIC_KEY}" >> "${AUTH_KEYS}"
fi

if [ -n "${SSH_GITHUB_KEYS_USER:-}" ]; then
  if ! curl -sfL --max-time 10 "https://github.com/${SSH_GITHUB_KEYS_USER}.keys" >> "${AUTH_KEYS}"; then
    echo "entrypoint: WARN failed to fetch keys for github.com/${SSH_GITHUB_KEYS_USER}" >&2
  fi
fi

chmod 600 "${AUTH_KEYS}"
chown "${APP_USER}:${APP_USER}" "${AUTH_KEYS}"

if [ ! -s "${AUTH_KEYS}" ]; then
  echo "entrypoint: WARN no SSH keys configured; SSH logins will fail." \
       "Set SSH_PUBLIC_KEY and/or SSH_GITHUB_KEYS_USER." >&2
fi

# ---- AI-context repo (clone on first start) --------------------------------
if [ -n "${AI_CONTEXT_REPO:-}" ]; then
  AI_CONTEXT_DIR="${AI_CONTEXT_DIR:-${APP_HOME}/ai-context}"
  target="${AI_CONTEXT_DIR}/$(basename "${AI_CONTEXT_REPO%.git}")"
  if [ ! -d "${target}" ]; then
    install -d -m 755 -o "${APP_USER}" -g "${APP_USER}" "${AI_CONTEXT_DIR}"
    echo "entrypoint: cloning ${AI_CONTEXT_REPO} -> ${target}"
    runuser -u "${APP_USER}" -- git clone "${AI_CONTEXT_REPO}" "${target}" \
      || echo "entrypoint: WARN failed to clone ${AI_CONTEXT_REPO}" >&2
  fi
fi

# ---- Apply firewall, then exec sshd ---------------------------------------
/usr/local/bin/init-firewall.sh || echo "entrypoint: WARN firewall setup failed" >&2
exec /usr/sbin/sshd -D
