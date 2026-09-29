# MT5 Web Replicator

Ruby on Rails application to receive, organize, and replicate trading information coming from MT5/MQL to a web backend. The project centralizes admin dashboards, accounts, customers, plans, invoices, payment integrations, and APIs to manage the distribution of orders and events across multiple accounts.

## Related repository

- Python/MQL client for MetaTrader: [`brenoperucchi/python-signal`](https://github.com/brenoperucchi/python-signal)

Use both repositories together when you need the full flow: `python-signal` runs close to MetaTrader and external signal sources; this repository receives, validates, organizes, and manages the data on the web backend.

## Stack

- Ruby 3.1.7
- Rails 7.0 (Zeitwerk)
- PostgreSQL
- Redis and Sidekiq for background jobs
- Webpacker, Tailwind CSS, Bootstrap, and Alpine.js
- Devise, Pundit, Administrate, Stripe (payments), and Telegram Bot
- I18n: English by default, Brazilian Portuguese (`pt-BR`) available

## Main areas

- `app/controllers/api`: versioned APIs for copy/slave/store, MT5, and external integrations.
- `app/controllers/admin`, `app/controllers/control`, and `app/controllers/panel`: administrative and operational interfaces.
- `app/models/message`: MetaTrader/Telegram message processing.
- `app/services`: auxiliary trade rules and data formatting for APIs.
- `app/views/layouts`: landing pages, dashboard, and admin layouts.

## Requirements

- Ruby 3.1.7 (e.g. via rbenv or asdf)
- PostgreSQL (the app connects with the password in `DATABASE_PASSWORD`; see `config/database.yml`)
- Node.js and Yarn (Webpacker assets)
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
from the admin once the store exists.

## Environment variables and credentials

See `.env.example` for the full list with a short explanation of each. The essentials:

| Variable | Purpose |
| --- | --- |
| `DATABASE_PASSWORD` | PostgreSQL password |
| `SECRET_KEY_BASE` | Required in production (or use Rails credentials) |
| `REDIS_URL` | Redis for Sidekiq / Action Cable |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | Stripe fallback keys (see below) |
| `PAYMENT_CURRENCY` | Checkout currency, default `usd` |
| `RECAPTCHA_SITE_KEY`, `RECAPTCHA_SECRET_KEY` | reCAPTCHA on public forms |
| `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_API_NUMBER` | Telegram settings used when seeding the store |

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
3. Currency: `PAYMENT_CURRENCY` (ISO code, default `usd`).

After checkout Stripe sends the customer back to `/payments/<invoice_id>/return/<kind>`.

## Language

English is the default locale; `pt-BR` is available. The locale is chosen per request
from `?locale=`, then the browser's `Accept-Language`, then the store's *language*
setting, then the default (`en`). Translations live in `config/locales/`.

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

The project has a Capistrano configuration:

```bash
bundle exec cap production deploy
```

Review `config/deploy/*.rb`, server environment variables, and credentials before publishing a new release.

## Checklist before making it public

- Remove local keys from Git, especially `config/credentials/*.key` files.
- Rotate any secret that has already been committed to Git history.
- Clean up the repository history before changing visibility on GitHub.
- Review seeds, fixtures, and factories to ensure they contain only fictitious data.
- Define the project's license, in case it is distributed publicly.

## Partnership

Interested in continuing, co-maintaining, or partnering on this project? Get in touch at bperucchi@gmail.com to discuss collaboration, licensing terms, or a handover.
