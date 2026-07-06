# MT5 Web Replicator

Ruby on Rails application to receive, organize, and replicate trading information coming from MT5/MQL to a web backend. The project centralizes admin dashboards, accounts, customers, plans, invoices, payment integrations, and APIs to manage the distribution of orders and events across multiple accounts.

## Related repository

- Python/MQL client for MetaTrader: [`brenoperucchi/python-signal`](https://github.com/brenoperucchi/python-signal)

Use both repositories together when you need the full flow: `python-signal` runs close to MetaTrader and external signal sources; this repository receives, validates, organizes, and manages the data on the web backend.

## Stack

- Ruby 2.7.8
- Rails 6.1.7.10
- PostgreSQL
- Redis and Sidekiq for background jobs
- Webpacker, Tailwind CSS, Bootstrap, and Alpine.js
- Devise, Pundit, Administrate, Pay, Stripe, Mercado Pago, and Telegram Bot

## Main areas

- `app/controllers/api`: versioned APIs for copy/slave/store, MT5, and external integrations.
- `app/controllers/admin`, `app/controllers/control`, and `app/controllers/panel`: administrative and operational interfaces.
- `app/models/message`: MetaTrader/Telegram message processing.
- `app/services`: auxiliary trade rules and data formatting for APIs.
- `app/views/layouts`: landing pages, dashboard, and admin layouts.

## Local setup

Install dependencies:

```bash
bundle install
yarn install
```

Prepare the database:

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

You can also use the standard setup script:

```bash
bin/setup
```

## Environment variables and credentials

The project uses Rails credentials and environment variables. For local development, configure at least:

```bash
DATABASE_PASSWORD=
SECRET_KEY_BASE=
REDIS_URL=redis://localhost:6379/0
TELEGRAM_API_ID=
TELEGRAM_API_HASH=
TELEGRAM_API_NUMBER=
```

Payment integrations also depend on the corresponding Stripe and Mercado Pago credentials, configured either in the `Payment`/`PaymentMethod` records or in credentials, depending on the flow used.

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
bundle exec rspec
bin/rails test
```

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
