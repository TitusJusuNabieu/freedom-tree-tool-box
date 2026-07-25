#!/usr/bin/env bash
# Freedom Tree — full server bootstrap
# Run this once right after cloning onto the target Ubuntu server:
#   bash scripts/setup.sh
#
# Installs Node, pnpm, PostgreSQL, PM2 and Caddy as needed, then builds the
# app and brings it up as a persistent service (PM2) behind a reverse proxy
# (Caddy). Safe to re-run — every step is idempotent.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_ENV="$REPO_DIR/apps/web/.env.production.local"
LOG_PREFIX="[ft-setup]"

info() { echo "$LOG_PREFIX  $*"; }
ok()   { echo "$LOG_PREFIX ✓ $*"; }
warn() { echo "$LOG_PREFIX ⚠ $*"; }
fail() { echo "$LOG_PREFIX ✗ $*" >&2; exit 1; }

cd "$REPO_DIR"

HAS_APT=0
command -v apt-get >/dev/null 2>&1 && HAS_APT=1

# ── System packages (Debian/Ubuntu) ────────────────────────────────────────────
if [[ "$HAS_APT" -eq 1 ]]; then
  info "Installing base system packages (curl, git, build-essential, openssl)..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq curl git build-essential ca-certificates openssl
  ok "Base system packages ready"
fi

# ── Node.js ──────────────────────────────────────────────────────────────────
NODE_MAJOR_REQUIRED=20
NODE_INSTALL_MAJOR=22   # LTS installed when Node is missing/too old — change if needed

CURRENT_NODE_MAJOR=0
command -v node >/dev/null 2>&1 && CURRENT_NODE_MAJOR="$(node -e 'process.stdout.write(process.version.split(".")[0].slice(1))')"

if [[ "$CURRENT_NODE_MAJOR" -lt "$NODE_MAJOR_REQUIRED" ]]; then
  if [[ "$HAS_APT" -eq 1 ]]; then
    info "Installing Node.js $NODE_INSTALL_MAJOR via NodeSource..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_INSTALL_MAJOR}.x" | sudo -E bash -
    sudo apt-get install -y -qq nodejs
    ok "Node $(node --version) installed"
  else
    fail "Node.js $NODE_MAJOR_REQUIRED+ not found and no apt-based auto-install available on this system.
Install Node manually: https://nodejs.org"
  fi
else
  ok "Node $(node --version) found"
fi

# ── pnpm ─────────────────────────────────────────────────────────────────────
if ! command -v pnpm >/dev/null 2>&1; then
  info "pnpm not found, installing via corepack..."
  corepack enable 2>/dev/null || sudo corepack enable
  corepack prepare pnpm@9.15.0 --activate
fi
ok "pnpm $(pnpm --version) found"

# ── PM2 ───────────────────────────────────────────────────────────────────────
if ! command -v pm2 >/dev/null 2>&1; then
  info "Installing PM2..."
  npm install -g pm2 2>/dev/null || sudo npm install -g pm2
fi
ok "PM2 $(pm2 --version) found"

# ── Caddy ─────────────────────────────────────────────────────────────────────
setup_caddy() {
  if [[ "$HAS_APT" -ne 1 ]]; then
    warn "Not on an apt-based system — skipping Caddy install/config. Set up a reverse proxy manually."
    return
  fi

  if ! command -v caddy >/dev/null 2>&1; then
    info "Installing Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq caddy
    ok "Caddy installed"
  else
    ok "Caddy already present"
  fi

  sudo touch /etc/caddy/Caddyfile
  if ! sudo grep -q "reverse_proxy localhost:3001" /etc/caddy/Caddyfile; then
    info "Adding Freedom Tree block to /etc/caddy/Caddyfile..."
    sudo tee -a /etc/caddy/Caddyfile < "$REPO_DIR/scripts/Caddyfile.snippet" >/dev/null
    sudo caddy fmt --overwrite /etc/caddy/Caddyfile
  fi
  sudo systemctl enable --now caddy >/dev/null 2>&1 || true
  sudo systemctl reload caddy
  ok "Caddy configured and reloaded"
}
setup_caddy

# ── Install project dependencies ────────────────────────────────────────────────
info "Installing dependencies (pnpm install)..."
pnpm install
ok "Dependencies installed"

# ── Production env file ────────────────────────────────────────────────────────
if [[ ! -f "$WEB_ENV" ]]; then
  info "Creating apps/web/.env.production.local..."

  if [[ -z "${PUBLIC_URL:-}" ]]; then
    DETECTED_IP="$(curl -fsSL --max-time 3 https://ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
    DEFAULT_URL="http://${DETECTED_IP:-YOUR_SERVER_IP}:8080"
    if [[ -t 0 ]]; then
      read -rp "$LOG_PREFIX  Public URL the app will be served at [$DEFAULT_URL]: " PUBLIC_URL_INPUT
      PUBLIC_URL="${PUBLIC_URL_INPUT:-$DEFAULT_URL}"
    else
      PUBLIC_URL="$DEFAULT_URL"
      warn "No TTY to prompt for a public URL — defaulting to $PUBLIC_URL (set PUBLIC_URL env var to override)"
    fi
  fi

  DB_NAME="freedomtree_prod"
  DB_USER="freedomtree"
  DB_PASS="$(openssl rand -hex 16)"
  DB_URL="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME"

  cp "$REPO_DIR/scripts/.env.production.example" "$WEB_ENV"
  sed -i.bak \
    -e "s#^DATABASE_URL=.*#DATABASE_URL=\"$DB_URL\"#" \
    -e "s#^JWT_ACCESS_SECRET=.*#JWT_ACCESS_SECRET=\"$(openssl rand -base64 32)\"#" \
    -e "s#^NEXTAUTH_SECRET=.*#NEXTAUTH_SECRET=\"$(openssl rand -base64 32)\"#" \
    -e "s#^NEXTAUTH_URL=.*#NEXTAUTH_URL=\"$PUBLIC_URL\"#" \
    "$WEB_ENV" && rm -f "$WEB_ENV.bak"
  ok "Created apps/web/.env.production.local"
else
  ok "apps/web/.env.production.local already exists, leaving it untouched"
fi

DB_URL="$(grep '^DATABASE_URL=' "$WEB_ENV" | cut -d'=' -f2- | tr -d '"')"
PUBLIC_URL="$(grep '^NEXTAUTH_URL=' "$WEB_ENV" | cut -d'=' -f2- | tr -d '"')"

# ── Mobile app API URL ────────────────────────────────────────────────────────
# The Flutter app posts reports to a hardcoded default base URL (overridable via
# --dart-define, but real devices in the field run the hardcoded default) — keep
# it in sync with whatever server this script just wired up.
API_URL="$PUBLIC_URL/api"
MOBILE_API_CONFIG="$REPO_DIR/apps/mobile/lib/core/network/api_config.dart"
if [[ -f "$MOBILE_API_CONFIG" ]]; then
  if ! grep -qF "return '$API_URL';" "$MOBILE_API_CONFIG"; then
    sed -i.bak -E "s#return '[^']*';#return '$API_URL';#" "$MOBILE_API_CONFIG" && rm -f "$MOBILE_API_CONFIG.bak"
    ok "Updated mobile app's default API URL to $API_URL"
    warn "Commit apps/mobile/lib/core/network/api_config.dart and rebuild the mobile app for this to reach real devices"
  else
    ok "Mobile app's default API URL already matches ($API_URL)"
  fi
fi

# ── PostgreSQL ────────────────────────────────────────────────────────────────
if [[ "$DB_URL" =~ ^postgres(ql)?://([^:]+):([^@]+)@localhost:([0-9]+)/(.+)$ ]]; then
  DB_USER="${BASH_REMATCH[2]}"
  DB_PASS="${BASH_REMATCH[3]}"
  DB_PORT="${BASH_REMATCH[4]}"
  DB_NAME="${BASH_REMATCH[5]}"

  if [[ "$HAS_APT" -eq 1 ]]; then
    [[ "$DB_PORT" == "5432" ]] || fail "DATABASE_URL uses port $DB_PORT, but native Postgres installs listen on 5432.
Either change the port in DATABASE_URL to 5432, or point it at an already-running Postgres."

    if ! command -v psql >/dev/null 2>&1; then
      info "Installing Postgres..."
      sudo apt-get install -y -qq postgresql postgresql-contrib
      ok "Postgres installed"
    fi
    sudo systemctl enable --now postgresql >/dev/null 2>&1 || true

    info "Creating role/database ($DB_USER / $DB_NAME) if missing..."
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" \
      | grep -q 1 || sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
    # Keep the role's password in sync with the env file in case it already existed
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" >/dev/null
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" \
      | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    ok "Role/database ready"
  else
    warn "Not on an apt-based system — skipping automatic Postgres install. Ensure DATABASE_URL is reachable."
  fi
else
  warn "DATABASE_URL doesn't point at a local Postgres — assuming it's an external/managed database."
fi

# ── Prisma client ─────────────────────────────────────────────────────────────
info "Generating Prisma client..."
pnpm exec prisma generate
ok "Prisma client generated"

# ── Build, migrate, and start under PM2 ─────────────────────────────────────────
info "Running deploy (migrate + build + PM2 start)..."
bash "$REPO_DIR/scripts/deploy.sh"

# ── Seed demo data ────────────────────────────────────────────────────────────
info "Seeding demo data..."
DATABASE_URL="$DB_URL" pnpm exec node --import=tsx prisma/seed.ts
ok "Seed complete"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
ok "Setup complete!"
echo ""
echo "  Dashboard URL:  $PUBLIC_URL"
echo "  Mobile API URL: $API_URL   (must match apps/mobile/lib/core/network/api_config.dart)"
echo "  PM2:            pm2 status / pm2 logs freedomtree-web"
echo "  Redeploy:       bash scripts/deploy.sh"
echo ""
echo "  Demo logins (seeded, password: password123):"
echo "    admin        — ADMIN role"
echo "    fieldworker1 — FIELD_WORKER role"
