# MT5 Web Replicator

Aplicacao Ruby on Rails para receber, organizar e replicar informacoes de trading vindas do MT5/MQL para um backend web. O projeto centraliza dashboards administrativos, contas, clientes, planos, faturas, integracoes de pagamento e APIs para gerenciar a distribuicao de ordens e eventos entre multiplas contas.

## Stack

- Ruby 2.7.8
- Rails 6.1.7.10
- PostgreSQL
- Redis e Sidekiq para jobs em background
- Webpacker, Tailwind CSS, Bootstrap e Alpine.js
- Devise, Pundit, Administrate, Pay, Stripe, Mercado Pago e Telegram Bot

## Principais areas

- `app/controllers/api`: APIs versionadas para copy/slave/store, MT5 e integracoes externas.
- `app/controllers/admin`, `app/controllers/control` e `app/controllers/panel`: interfaces administrativas e operacionais.
- `app/models/message`: processamento de mensagens MetaTrader/Telegram.
- `app/services`: regras auxiliares de trade e formatacao de dados para APIs.
- `app/views/layouts`: landing pages, dashboard e layouts administrativos.

## Configuracao local

Instale as dependencias:

```bash
bundle install
yarn install
```

Prepare o banco:

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

Tambem e possivel usar o script padrao:

```bash
bin/setup
```

## Variaveis e credenciais

O projeto usa Rails credentials e variaveis de ambiente. Para desenvolvimento local, configure pelo menos:

```bash
DATABASE_PASSWORD=
SECRET_KEY_BASE=
REDIS_URL=redis://localhost:6379/0
TELEGRAM_API_ID=
TELEGRAM_API_HASH=
TELEGRAM_API_NUMBER=
```

As integracoes de pagamento tambem dependem das credenciais correspondentes de Stripe e Mercado Pago configuradas no cadastro de `Payment`/`PaymentMethod` ou em credentials, conforme o fluxo usado.

## Rodando em desenvolvimento

Suba a aplicacao com Foreman:

```bash
bin/dev
```

Ou rode os processos separadamente:

```bash
bin/rails server
bin/webpack-dev-server
bundle exec sidekiq
```

## Testes

```bash
bundle exec rspec
bin/rails test
```

## Deploy

O projeto possui configuracao de Capistrano:

```bash
bundle exec cap production deploy
```

Revise `config/deploy/*.rb`, variaveis do servidor e credentials antes de publicar uma nova versao.

## Checklist antes de tornar publico

- Remover chaves locais do Git, especialmente arquivos `config/credentials/*.key`.
- Rotacionar qualquer segredo que ja tenha sido commitado em historico Git.
- Limpar o historico do repositorio antes de alterar a visibilidade no GitHub.
- Revisar seeds, fixtures e factories para garantir que contenham apenas dados ficticios.
- Definir a licenca do projeto, caso ele seja distribuido publicamente.
