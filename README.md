# MT5 Web Replicator

[![CI](https://github.com/brenoperucchi/mt5-web-replicator/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/brenoperucchi/mt5-web-replicator/actions/workflows/ci.yml)
[![Docker publish](https://github.com/brenoperucchi/mt5-web-replicator/actions/workflows/docker-publish.yml/badge.svg?branch=master)](https://github.com/brenoperucchi/mt5-web-replicator/actions/workflows/docker-publish.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.3.10-CC342D?logo=ruby&logoColor=white)](.ruby-version)
[![Rails](https://img.shields.io/badge/rails-8.1-D30001?logo=rubyonrails&logoColor=white)](Gemfile)
[![Docker image](https://img.shields.io/badge/image-ghcr.io-2496ED?logo=docker&logoColor=white)](https://github.com/brenoperucchi/mt5-web-replicator/pkgs/container/mt5-web-replicator)
[![License: PolyForm Noncommercial](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE.md)

Ruby on Rails application to receive, organize, and replicate trading information coming from MT5/MQL to a web backend. The project centralizes admin dashboards, accounts, customers, plans, invoices, payment integrations, and APIs to manage the distribution of orders and events across multiple accounts.

## TradeMirror (Phase 1, in progress)

TradeMirror is the new copy-trading product (#78) built from the approved design
[`docs/design/0001-copy-core.md`](docs/design/0001-copy-core.md) (#77). It does not replace
anything in the Rails app yet.

- **Copy Server** (FastAPI, Python 3.12, package `copycore`): [`server/`](server/README.md).
- **TradeMirror EA** for MetaTrader 5 (one EA, master or slave role, protocol v4 with a durable
  journal and results outbox): [`ea/mt5/`](ea/mt5/README.md).
- Protocol v4 scenario catalog: [`docs/protocol/v4/scenarios/`](docs/protocol/v4/scenarios/).

## Quick start (Docker)

Try it locally with nothing but Docker:

```bash
git clone https://github.com/brenoperucchi/mt5-web-replicator.git
cd mt5-web-replicator
docker compose up
```

Open <http://localhost:3000> once the `web` container reports healthy (first boot creates
the database and loads demo data, about a minute). Logins:

| Role | Email | Password | Start at |
| --- | --- | --- | --- |
| Admin (store owner) | `admin@example.com` | `password123` | <http://localhost:3000/admin>, <http://localhost:3000/control> |
| Demo customer | `demo@example.com` | `password123` | <http://localhost:3000/panel> |

Sign in at <http://localhost:3000/users/sign_in>. What to explore:

- **Admin** (`/admin`): orders, transactions, accounts, traces, customers, plans, invoices.
- **Control panel** (`/control`): accounts, portfolios (`/control/traces`), orders,
  slave trades, invoices.
- **Customer panel** (`/panel`): the demo customer's dashboard and invoices.
- **Portfolio page** (`/dashboard/store-1/DemoSignal`): public stats of the demo portfolio.

The demo data (`SEED_DEMO=1`, see `db/seeds/demo.rb`) is a copy portfolio "DemoSignal" with
one master account and two slave accounts, 13 EURUSD/GBPUSD/XAUUSD/US500 trades over the last
30 days (10 closed, 3 open) replicated to both slaves through the same v3 API flow the
MetaTrader clients use, and two invoices (one paid, one due). Stripe is not configured, so
paying an invoice won't work unless you set `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET`.

- Stop: `docker compose down`. Reset everything (database, uploads): `docker compose down -v`.
- Port 3000 busy? `PORT=3100 docker compose up` (and `APP_DOMAIN=localhost:3100`).
- The image is prebuilt on GHCR (`ghcr.io/brenoperucchi/mt5-web-replicator`, built from
  `master` after CI passes); `docker compose up --build` builds it from your checkout instead.
- Every default in `docker-compose.yml` (secret key, passwords, demo logins) is for a
  **local trial only**. Deploy for real with Kamal (see [Deploy](#deploy)).

## Related repository

- Python/MQL client for MetaTrader: [`brenoperucchi/python-signal`](https://github.com/brenoperucchi/python-signal)

Use both repositories together when you need the full flow: `python-signal` runs close to MetaTrader and external signal sources; this repository receives, validates, organizes, and manages the data on the web backend.

## Stack
- Ruby 3.3.10
- Rails 8.1 (Zeitwerk, `load_defaults 8.1`), Sprockets + Shakapacker for assets
- Rails 7.0 (Zeitwerk)
- PostgreSQL
- Redis and Sidekiq for background jobs
- Shakapacker (webpack), Tailwind CSS, Bootstrap, and Alpine.js
- Devise, Pundit, Administrate, and Stripe (payments)
- I18n: English by default, Brazilian Portuguese (`pt-BR`) available

## Main areas

- `app/controllers/api`: versioned APIs for copy/slave/store, MT5, and external integrations.
- `app/controllers/admin`, `app/controllers/control`, and `app/controllers/panel`: administrative and operational interfaces.
- `app/models/message`: MetaTrader message processing (Telegram parts are dormant, see Roadmap).
- `app/services`: auxiliary trade rules and data formatting for APIs.
- `app/views/layouts`: landing pages, dashboard, and admin layouts.

## Requirements

- Ruby 3.3.10 (e.g. via rbenv or asdf), or just Docker
- PostgreSQL (the app connects with the password in `DATABASE_PASSWORD`; see `config/database.yml`)
- Node.js and Yarn (Shakapacker assets)
- Redis (Sidekiq jobs and Action Cable)

## Local setup

```bash
cp .env.example .env        # then fill in the values you need
bundle install
yarn install
bin/rails db:create db:schema:load db:seed
```

`.env` is gitignored and loaded at boot by the `dotenv` gem (variables already set in
the shell take precedence). `.env.example` documents every variable the app reads.

In development, `db:seed` creates a store, a plan, an admin user
(`SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD`, defaults `admin@example.com` / `password123`)
and a default Stripe payment row. Traces and customer plans are not seeded; create them
from the admin once the store exists, or run `SEED_DEMO=1 bin/rails db:seed` for the demo
dataset described in [Quick start](#quick-start-docker).

## Environment variables and credentials

See `.env.example` for the full list with a short explanation of each. The essentials:

| Variable | Purpose |
| --- | --- |
| `DATABASE_PASSWORD` | PostgreSQL password |
| `SECRET_KEY_BASE` | Required in production (or use Rails credentials) |
| `REDIS_URL` | Redis for Sidekiq / Action Cable |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Stripe fallback keys (see below) |
| `PAYMENT_CURRENCY` | Checkout currency, default `usd` (`config/deploy.yml` sets `brl`) |
| `RECAPTCHA_SITE_KEY`, `RECAPTCHA_SECRET_KEY` | reCAPTCHA on public forms |

## Payments (Stripe)

Billing is provider-agnostic (`PaymentMethod` + `Payment` rows, with an adapter per
provider in `app/models/payment_method/`); Stripe is the default and only provider shipped.

1. Credentials: set the secret key and webhook signing secret on the `Payment` row
   (`api_token` / `webhook_token`, editable in the admin). When a row leaves them blank,
   `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` are used instead.
2. Webhook: in the Stripe dashboard, add an endpoint pointing to
   `https://<your-domain>/payments/webhook/<payment_id>` (`<payment_id>` is the id of the
   `Payment` row; `db:seed` prints it). Subscribe to:
   - `checkout.session.completed`
   - `checkout.session.async_payment_succeeded`
   - `checkout.session.async_payment_failed`
   - `checkout.session.expired`
   - `charge.refunded`

   Register **one webhook endpoint per distinct webhook secret**, not one per `Payment`:
   Stripe signs each endpoint with its own secret, so every `Payment` that leaves
   `webhook_token` blank shares the single `STRIPE_WEBHOOK_SECRET` and is served by one
   endpoint (any of those payments' ids). An endpoint processes an invoice only when the
   invoice's `Payment` resolves to the same secret, so a store with its own credentials
   never touches another store's invoices.
3. Currency: `PAYMENT_CURRENCY` (ISO code, default `usd`). This deployment bills in BRL:
   `config/deploy.yml` sets `PAYMENT_CURRENCY: brl`.

Webhooks are rejected (400) when no signing secret is configured. Invoice state only moves
forward (paid from pending/to_paid/denied, denied from pending/to_paid, refunded from paid);
an expired session leaves the invoice payable, and only a full `charge.refunded` marks it
refunded. Checkout reuses the invoice's open session (expiring it first if the invoice amount
or currency changed) and never charges paid/refunded invoices.

#### Checkout attempt lifecycle

Each checkout attempt is tracked in `invoice.response`: `checkout_attempt`,
`checkout_idempotency_key`, `checkout_amount_cents`, `checkout_currency`,
`checkout_session_id` and `checkout_status`:

- `creating`: the attempt (key, amount/currency, the full create payload in
  `checkout_create_params` and the creating `checkout_payment_id`) is saved *before* calling
  Stripe. If the create fails inconclusively (network error, timeout, 5xx, 409/429, or an
  idempotency conflict) it stays `creating` and the next send retries with the same key, the
  stored payload and that Payment's credentials, so Stripe returns the same session even if
  the customer's name/email or the store URLs changed meanwhile.
  If the invoice amount changed meanwhile, the recovered session is then expired and a new
  attempt opened for the new amount. A definitive 4xx rejection closes it as `rejected`.
- `open`: session published; reused while amount/currency match.
- `processing`: `complete` but `unpaid` (async methods such as boleto). No new checkout is
  issued ("Invoice Not Sended!") until this session is confirmed failed or paid.
- `failed` (`async_payment_failed` of this session), `expired`, `rejected`: closed; the next
  send opens exactly one new attempt. `paid`: closed for good.

Statuses only move forward and are changed only by events/lookups of the *current* session;
late events of an older session never release a new attempt (a late paid event still marks
the invoice paid). The invoice's `denied` state is history, not attempt state: a migrated
`denied` invoice gets one attempt and then follows the rules above. When Stripe cannot be
reached to check or expire the current session, checkout also waits.

#### Recovering an inconclusive attempt (operator)

If an invoice stays stuck (lookups keep failing, e.g. the store's `Payment` was switched to
another Stripe account while keeping the old session id, or a `processing` session whose
failure webhook never arrived):

Editing `checkout_status` alone does **not** unblock it: while `checkout_session_id` is set,
every send retrieves that session with the *current* credentials, and a 404/error keeps
waiting. Recover in one of two ways:

1. **Preferred:** restore access to the original Stripe account (put its keys back on the
   store's `Payment`). The next send, the customer return (`sync`) or a webhook then
   reconciles the session and updates the status on its own.
2. **Explicit reconciliation**, when the original account cannot be used again:
   1. Look up the attempt's `checkout_session_id` (or, for `creating`, the
      `checkout_idempotency_key` in the request logs) in the **original** Stripe account.
   2. Confirm the financial result (check its PaymentIntent): paid, failed, or expired
      without payment.
   3. Only then record it, which stores the outcome, note and old session under
      `checkout_reconciled` and detaches the session:

      ```ruby
      invoice = Invoice.find(ID)
      invoice.response.slice(:checkout_session_id, :checkout_status, :checkout_idempotency_key)
      invoice.reconcile_checkout!(outcome: 'failed', note: 'pi_... requires_payment_method in old account, checked by NAME')
      # outcome: 'paid' (also marks the invoice paid), 'failed' or 'expired'
      ```

      After `failed`/`expired` the next send opens exactly one new attempt.

Never blindly clear `checkout_session_id` (or call `reconcile_checkout!` on a guess): an
unresolved session may still be paid, and a new attempt would allow a double charge.

### Migrating from MercadoPago

MercadoPago is no longer supported. To move existing stores to Stripe:

```bash
DRY_RUN=1 bin/rails billing:migrate_mercadopago_to_stripe   # preview
bin/rails billing:migrate_mercadopago_to_stripe
```

It ensures each store has a Stripe `Payment` (blank keys, so the `STRIPE_*` ENV fallback
applies) and repoints the store, its customer plans and its open invoices (pending, to_paid
and denied, clearing their old payment link) to it. Legacy MercadoPago rows are kept for
history. The task is idempotent. It also lists (also with `DRY_RUN=1`) pre-existing Stripe
`Payment` rows it reuses that carry their own credentials, flagging an `api_token` not
starting with `sk_`/`rk_` or a `webhook_token` not starting with `whsec_`.

Legacy store whose `payment_id` points to **another store's** Stripe `Payment` and that has
no `Payment` of its own before migration: run the migration (it creates the store's own
Stripe `Payment`), then verify that `store.billing_payment` resolves to that own payment
(the cross-store FK is ignored by the fallback), and audit historical invoices/customer plans
that still reference the other store's payment, since the guard only protects future charges.
Never restore a global (cross-store) payment fallback as a fix.

### Legacy pay gem tables

Migration `20260929000000_drop_pay_tables` drops empty `pay_*` tables and renames any that
still hold rows to `legacy_pay_*`, so no data is lost. Drop them manually once no longer needed.

After checkout Stripe sends the customer back to `/payments/<invoice_id>/return/<kind>`.

## Language

English is the default locale; `pt-BR` is available. The locale is chosen per request
from `?locale=`, then the browser's `Accept-Language`, then the store's *language*
setting, then the default (`en`). Translations live in `config/locales/`.
Stores created before English became the default have their language backfilled to `pt-BR`
(migration `20260929120000_backfill_store_language`).

## Running in development

Start the application with Foreman:

```bash
bin/dev
```

Or run the processes separately:

```bash
bin/rails server
bin/webpack-dev-server
bundle exec sidekiq
```

## Tests

```bash
RAILS_ENV=test bin/rails db:create db:schema:load
bundle exec rspec
```

Note: `spec/spec_helper.rb` sets `config.fail_fast = true`, so the run stops at the
first failure. Use `bundle exec rspec --no-fail-fast` to see every failure.

## Deploy

The app ships as a Docker image (`Dockerfile`) and deploys with [Kamal](https://kamal-deploy.org) (`config/deploy.yml`):

- `web`: Puma behind kamal-proxy (TLS via Let's Encrypt, health check on `/up`)
- `worker`: Sidekiq
- `cron`: `bin/billing-cron` runs `Invoice.generate_month_customers` every minute (errors are reported and the loop keeps going)
- accessories: PostgreSQL 16 and Redis 7; Active Storage uploads live in the `mt5_web_replicator_storage` volume

1. Fill the `<...>` placeholders in `config/deploy.yml` (server IP, domain, registry user).
2. Export the variables referenced in `.kamal/secrets` (or point them at a password manager).
   `POSTGRES_PASSWORD` goes into `DATABASE_URL`, so keep it URL-safe (`openssl rand -hex 32`).
3. `bin/kamal setup` for the first deploy, then `bin/kamal deploy`.

The web container runs `db:prepare` on boot, so the first boot also creates the database and runs `db:seed`
(set `SEED_ADMIN_PASSWORD`, required in production).

To try the production image locally:

```bash
docker build -t mt5_web_replicator .
docker run --rm -p 3000:80 -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e DATABASE_URL=postgres://user:pass@host:5432/db -e REDIS_URL=redis://host:6379/0 mt5_web_replicator
```

## Checklist before making it public

- Remove local keys from Git, especially `config/credentials/*.key` files.
- Rotate any secret that has already been committed to Git history.
- Clean up the repository history before changing visibility on GitHub.
- Review seeds, fixtures, and factories to ensure they contain only fictitious data.

## Roadmap / Future features

- **Telegram signal ingestion** (disabled; enable with `ENABLE_TELEGRAM=1` — experimental).
  Traces of kind `telegram` read trading signals posted in Telegram channels (a companion
  Python/TDLib client polled `/api/*/stores/telegram/python` for the stores' `telegram_api_*`
  credentials and pushed chat history back), parsed them into `Messages::Telegram` records
  and turned them into orders replicated to the slave accounts; a Telegram bot ("Alfred")
  could also post open/modify/close notifications to a store's group. The code is kept but
  nothing runs unless the flag is on: the `telegram-bot-ruby` gem isn't loaded, the
  `/telegram/python` endpoints return 404, the webhook API isn't mounted and no Telegram
  ENV vars or credentials are needed (the optional ones are listed in `.env.example`).

## License

This project is **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).

- **Free for noncommercial use.** You can read, run, test, modify and share it for personal use, study, research, evaluation, or at a nonprofit, school or public institution.
- **Commercial use needs a separate license.** This includes running it for a business, offering it as a service, or using it to manage paying customers' accounts. Contact bperucchi@gmail.com to discuss terms.

The companion client, [`python-signal`](https://github.com/brenoperucchi/python-signal), is published under the same license.

## Contributing

Pull requests are welcome. Before your first pull request can be merged, you will be asked to sign the [Contributor License Agreement](CLA.md) by leaving a comment on the pull request. It keeps the project able to offer commercial licenses while your contribution stays credited to you.

## Partnership

Interested in collaborating on this project or building something on top of it commercially? Get in touch at bperucchi@gmail.com.
