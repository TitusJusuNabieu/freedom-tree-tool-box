#!/usr/bin/env bash
# Freedom Tree — local dev bootstrap
# Run this once right after cloning the repo:
#   bash scripts/setup.sh
#
# Safe to re-run: every step is idempotent (won't clobber existing env files,
# won't fail on already-applied migrations or already-seeded data).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_ENV="$REPO_DIR/.env"
WEB_ENV="$REPO_DIR/apps/web/.env.local"
LOG_PREFIX="[ft-setup]"

info() { echo "$LOG_PREFIX  $*"; }
ok()   { echo "$LOG_PREFIX ✓ $*"; }
warn() { echo "$LOG_PREFIX ⚠ $*"; }
fail() { echo "$LOG_PREFIX ✗ $*" >&2; exit 1; }

cd "$REPO_DIR"

# ── Pre-flight: Node ─────────────────────────────────────────────────────────
command -v node >/dev/null 2>&1 || fail "Node.js not found. Install Node 20+ first (https://nodejs.org)."
NODE_MAJOR="$(node -e 'process.stdout.write(process.version.split(".")[0].slice(1))')"
[[ "$NODE_MAJOR" -ge 20 ]] || warn "Node $(node --version) detected — 20+ is recommended."
ok "Node $(node --version) found"

# ── Pre-flight: pnpm ─────────────────────────────────────────────────────────
if ! command -v pnpm >/dev/null 2>&1; then
  info "pnpm not found, installing via corepack..."
  corepack enable
  corepack prepare pnpm@9.15.0 --activate
fi
ok "pnpm $(pnpm --version) found"

# ── Install dependencies ──────────────────────────────────────────────────────
info "Installing dependencies (pnpm install)..."
pnpm install
ok "Dependencies installed"

# ── Env files ──────────────────────────────────────────────────────────────────
DEFAULT_DB_URL="postgresql://freedomtree:freedomtree@localhost:5432/freedomtree_dev"

if [[ ! -f "$ROOT_ENV" ]]; then
  info "Creating .env..."
  cp "$REPO_DIR/.env.example" "$ROOT_ENV"
  sed -i.bak "s#^DATABASE_URL=.*#DATABASE_URL=\"$DEFAULT_DB_URL\"#" "$ROOT_ENV" && rm -f "$ROOT_ENV.bak"
  ok "Created .env (edit DATABASE_URL if your local Postgres differs)"
else
  ok ".env already exists, leaving it untouched"
fi

if [[ ! -f "$WEB_ENV" ]]; then
  info "Creating apps/web/.env.local..."
  cp "$REPO_DIR/apps/web/.env.example" "$WEB_ENV"
  JWT_SECRET="$(openssl rand -base64 32)"
  NEXTAUTH_SECRET="$(openssl rand -base64 32)"
  sed -i.bak \
    -e "s#^DATABASE_URL=.*#DATABASE_URL=\"$DEFAULT_DB_URL\"#" \
    -e "s#^JWT_ACCESS_SECRET=.*#JWT_ACCESS_SECRET=\"$JWT_SECRET\"#" \
    -e "s#^NEXTAUTH_SECRET=.*#NEXTAUTH_SECRET=\"$NEXTAUTH_SECRET\"#" \
    "$WEB_ENV" && rm -f "$WEB_ENV.bak"
  ok "Created apps/web/.env.local (secrets auto-generated)"
else
  ok "apps/web/.env.local already exists, leaving it untouched"
fi

# Keep DATABASE_URL in sync between the two files for this run's readiness check
DB_URL="$(grep '^DATABASE_URL=' "$WEB_ENV" | cut -d'=' -f2- | tr -d '"')"

# ── Prisma client ─────────────────────────────────────────────────────────────
info "Generating Prisma client..."
pnpm exec prisma generate
ok "Prisma client generated"

# ── Database readiness ────────────────────────────────────────────────────────
attempt_migrate() {
  DATABASE_URL="$DB_URL" pnpm exec prisma migrate deploy
}

info "Applying database migrations..."
if ! attempt_migrate; then
  warn "Could not reach the database at: $DB_URL"

  if command -v apt-get >/dev/null 2>&1 && [[ "$DB_URL" =~ ^postgres(ql)?://([^:]+):([^@]+)@localhost:([0-9]+)/(.+)$ ]]; then
    DB_USER="${BASH_REMATCH[2]}"
    DB_PASS="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_NAME="${BASH_REMATCH[5]}"

    if [[ "$DB_PORT" != "5432" ]]; then
      fail "DATABASE_URL uses port $DB_PORT, but native Postgres installs listen on 5432.
Either change the port in DATABASE_URL to 5432, or point it at an already-running Postgres."
    fi

    if ! command -v psql >/dev/null 2>&1; then
      info "Postgres not found — installing via apt..."
      sudo apt-get update -qq
      sudo apt-get install -y -qq postgresql postgresql-contrib
      ok "Postgres installed"
    fi
    sudo systemctl enable --now postgresql >/dev/null 2>&1 || true

    info "Creating role/database ($DB_USER / $DB_NAME) if missing..."
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" \
      | grep -q 1 || sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" \
      | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
    ok "Role/database ready"

    attempt_migrate || fail "Postgres is running but migrations still failed. Check the DATABASE_URL credentials match what was just created."
    ok "Postgres installed locally and migrations applied"
  else
    fail "No reachable database, and no apt-based auto-install available on this system.
Start a local Postgres matching DATABASE_URL in apps/web/.env.local, then re-run this script — it's safe to run again."
  fi
else
  ok "Migrations applied"
fi

# ── Seed data ──────────────────────────────────────────────────────────────────
info "Seeding demo data..."
DATABASE_URL="$DB_URL" pnpm run prisma:seed
ok "Seed complete"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
ok "Setup complete!"
echo ""
echo "  Start the dashboard:  pnpm dev:web"
echo "  Then open:            http://localhost:3000"
echo ""
echo "  Demo logins (seeded, password: password123):"
echo "    admin        — ADMIN role"
echo "    fieldworker1 — FIELD_WORKER role"
