# Brief Backend — Implementation Plan

> **Goal:** Build the complete API Gateway backend for Brief Pro — JWT auth, OpenRouter SSE proxy, Stripe billing, rate limiting, Docker deploy.

**Architecture:** FastAPI + SQLAlchemy + asyncpg → PostgreSQL. Redis for rate limiting. SSE pass-through to OpenRouter. Apple Sign-In for auth. Stripe for billing. Tailscale Funnel for deploy.

**Tech Stack:** Python 3.12+, FastAPI, SQLAlchemy 2.0 (async), Alembic, asyncpg, Redis (redis-py), httpx (async HTTP), PyJWT, Stripe Python SDK.

---

## Task 1: Scaffold project structure

**Files:** `pyproject.toml`, `Dockerfile`, `docker-compose.yml`, `.env.example`, `app/__init__.py`, `app/main.py`, `app/config.py`, `app/database.py`

Create the FastAPI project with async SQLAlchemy engine, config from env vars, health endpoint.

## Task 2: Database models

**Files:** `app/models.py`, `alembic/`, `alembic.ini`

Define 5 models: User, Subscription, UsageLog, RateLimit, RefreshToken. Run initial migration.

## Task 3: Auth — JWT + Apple Sign-In

**Files:** `app/auth.py`, `app/schemas/auth.py`, `app/routes/auth.py`

Implement Apple identity token verification (fetch Apple's JWKS, validate), JWT issue/verify/refresh. Endpoints: `POST /v1/auth/apple`, `POST /v1/auth/refresh`.

## Task 4: Auth middleware

**Files:** `app/dependencies.py`

Create `get_current_user` dependency that extracts and validates JWT from Authorization header. Returns user + subscription tier.

## Task 5: OpenRouter SSE proxy

**Files:** `app/routes/chat.py`, `app/schemas/chat.py`

`POST /v1/chat/completions` — validates JWT, checks rate limit, forwards to OpenRouter with Brief's API key, streams SSE response, logs usage.

## Task 6: Rate limiting

**Files:** `app/rate_limiter.py`

Redis-backed sliding window rate limiter. Enforces per-plan limits (Free: 10/min, Pro: 60/min). PostgreSQL fallback if Redis unavailable. Middleware integration.

## Task 7: Stripe billing

**Files:** `app/routes/billing.py`

`POST /v1/stripe/webhook` — handles `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`. Updates subscription status.

## Task 8: Account endpoint

**Files:** `app/routes/account.py`

`GET /v1/account` — returns subscription status, plan, period end, current usage (requests + tokens), rate limit caps.

## Task 9: Tests

**Files:** `tests/`

Test suite using pytest + httpx AsyncClient: auth flow, proxy (mock OpenRouter), rate limiter, billing webhooks, account endpoint.

## Task 10: Docker + deploy

**Files:** `docker-compose.yml` (finalize), `nginx.conf`

Docker Compose with app + Postgres + Redis. Tailscale Funnel config. Health check endpoints.

---

**Execution order:** 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10

**Commit after each task.**
