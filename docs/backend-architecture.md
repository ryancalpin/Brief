# Brief API Gateway — Backend Architecture

## Why a Backend?

Brief has two modes:

| Mode | How it works | Who it's for |
|------|-------------|--------------|
| **BYOK** (default) | User brings their own OpenRouter API key. All calls go direct from device → OpenRouter. | Open source, self-hosted |
| **App Store / Brief Pro** | Managed gateway. User authenticates with Apple Sign-In, gets a JWT. All AI calls go device → Gateway → OpenRouter. | Paid subscribers |

The backend IS the gateway. It exists so App Store users never need to know what OpenRouter is — they just subscribe and talk to Brief.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        iOS App                              │
│  APIGatewayService.swift                                    │
│    ├─ BYOK mode: direct → openrouter.ai (user's key)        │
│    └─ Gateway mode: JWT → api.brief.app (managed)           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    HTTPS / JWT
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    API Gateway (FastAPI)                     │
│                                                             │
│  /health                  → health check                    │
│  /v1/chat/completions     → proxy to OpenRouter (SSE)       │
│  /v1/auth/apple           → Apple Sign-In → JWT             │
│  /v1/auth/refresh         → refresh JWT                     │
│  /v1/account              → subscription + usage            │
│  /v1/stripe/webhook       → Stripe events                   │
│                                                             │
│  Rate limiter → Subscription tier → Usage log               │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    API key (server-side only)
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                      OpenRouter                              │
│  api.openrouter.ai/v1/chat/completions                      │
│  Models: Claude, GPT, Gemini, etc.                          │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────────┐
│       PostgreSQL          │
│  users, subscriptions,    │
│  usage_logs, rate_limits  │
└──────────────────────────┘
```

---

## Endpoints

### `GET /health`
Returns `{"status": "ok"}`. Used by the iOS app to check if the gateway is reachable before attempting requests. No auth required.

### `POST /v1/auth/apple`
**Request:**
```json
{
  "identity_token": "eyJ... (Apple ID token)",
  "authorization_code": "c... (optional, for server-side refresh)"
}
```

**Response:**
```json
{
  "access_token": "eyJ... (JWT, 24h expiry)",
  "refresh_token": "r... (opaque, 30d expiry)",
  "user": {
    "id": "usr_abc123",
    "subscription_status": "active",
    "plan": "pro_monthly"
  }
}
```

**Flow:**
1. Validate Apple identity token with Apple's public key
2. Upsert user in database (by `apple_user_id`)
3. Check subscription status (Stripe or App Store IAP)
4. Issue JWT with claims: `{sub: user_id, plan: "pro_monthly", exp: ...}`

### `POST /v1/auth/refresh`
**Request:** `{"refresh_token": "r..."}`
**Response:** `{"access_token": "eyJ...", "refresh_token": "r..."}` (rotated)

### `GET /v1/account`
**Headers:** `Authorization: Bearer <jwt>`
**Response:**
```json
{
  "subscription": {
    "status": "active",
    "plan": "pro_monthly",
    "current_period_end": "2026-06-12T00:00:00Z"
  },
  "usage": {
    "current_period_requests": 1423,
    "current_period_tokens": 284600,
    "rate_limit": {
      "requests_per_minute": 60,
      "requests_per_day": 5000
    }
  }
}
```

### `POST /v1/chat/completions`
**Headers:** `Authorization: Bearer <jwt>`, `Content-Type: application/json`

**Request body:** Same as [OpenRouter API](https://openrouter.ai/docs/api-reference/completions) — exact pass-through.

**Response:** Server-Sent Events (SSE) stream, also pass-through from OpenRouter.

**Gateway logic:**
1. Validate JWT, extract `user_id` and `plan`
2. Check rate limit for this user's tier
3. Inject Brief's own OpenRouter API key (never exposed to client)
4. Forward request to `https://openrouter.ai/api/v1/chat/completions`
5. Stream response back to client byte-for-byte
6. Log token usage (from `x-openrouter-tokens` or response body)

### `POST /v1/stripe/webhook`
Handles Stripe webhook events: `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`. Updates subscription status in database.

---

## Database Schema

```sql
-- Users table
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_user_id TEXT UNIQUE NOT NULL,
    email         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Subscriptions
CREATE TABLE subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id),
    status              TEXT NOT NULL,  -- 'active', 'past_due', 'canceled', 'trialing'
    plan                TEXT NOT NULL,  -- 'pro_monthly', 'pro_yearly'
    stripe_customer_id  TEXT,
    stripe_subscription_id TEXT,
    current_period_end  TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Usage logs (one row per API call)
CREATE TABLE usage_logs (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    model       TEXT NOT NULL,
    tokens_in   INTEGER NOT NULL DEFAULT 0,
    tokens_out  INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Rate limit counters (Redis-backed, this table is fallback)
CREATE TABLE rate_limits (
    user_id     UUID NOT NULL REFERENCES users(id),
    window      TEXT NOT NULL,  -- '1m', '1d'
    count       INTEGER NOT NULL DEFAULT 0,
    reset_at    TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, window)
);

-- Refresh tokens
CREATE TABLE refresh_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id),
    token_hash  TEXT UNIQUE NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## Rate Limiting Tiers

| Plan | Requests/min | Requests/day | Models |
|------|-------------|-------------|--------|
| **Free / Trial** | 10 | 200 | flash models only |
| **Pro Monthly** | 60 | 5,000 | all models |
| **Pro Yearly** | 120 | 10,000 | all models |

Implementation: Redis sliding window counters, fallback to PostgreSQL if Redis is down.

---

## Environment Variables

```bash
# Server
PORT=8080
HOST=0.0.0.0

# Auth
JWT_SECRET=xxx          # HS256 signing key
APPLE_TEAM_ID=xxx       # For Apple Sign-In verification
APPLE_BUNDLE_ID=com.brief.app

# OpenRouter
OPENROUTER_API_KEY=sk-or-xxx  # Brief's own key (never exposed to clients)

# Database
DATABASE_URL=postgresql://brief:xxx@localhost:5432/brief

# Stripe
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx

# Redis (optional, for rate limiting)
REDIS_URL=redis://localhost:6379
```

---

## Implementation Plan

### Phase 1: Core Gateway (2-3 days)
- FastAPI project scaffold (same pattern as PopRx backend)
- `POST /v1/chat/completions` — proxy to OpenRouter with SSE streaming
- `GET /health`
- Hardcoded rate limits, no auth (just API key in env)

### Phase 2: Auth (1-2 days)
- Apple Sign-In verification
- JWT issue/refresh flow
- `POST /v1/auth/apple`, `POST /v1/auth/refresh`
- Protected routes with JWT middleware

### Phase 3: Billing (1-2 days)
- Stripe integration (webhooks, checkout session)
- Subscription status tracking
- `GET /v1/account`
- `POST /v1/stripe/webhook`

### Phase 4: Rate Limiting & Usage (1 day)
- Redis-backed rate limiter
- Usage logging per user
- Tier enforcement

### Phase 5: Production (1 day)
- Tailscale Funnel for public HTTPS (same as PopRx)
- Docker Compose for local dev
- Health check monitoring
- `Config.xcconfig` updated with real URL

---

## iOS Integration (Already Done)

The `APIGatewayService.swift` already handles:

| Feature | How |
|---------|-----|
| Gateway URL from build config | Reads `API_GATEWAY_URL` from Info.plist (set via `Config.xcconfig`) |
| JWT storage | `KeychainService.shared.write(key: .gatewayJWT, ...)` |
| Health check before first use | `checkGatewayHealth()` pings `/health` |
| Auto-fallback to BYOK | If gateway unreachable, silently uses user's OpenRouter key |
| OpenRouter-compatible proxy | Calls the same `/chat/completions` shape — zero client changes |

The only iOS change when backend is live: set `API_GATEWAY_URL` in `Config.xcconfig`.
Everything else is handled transparently by `APIGatewayService`.
