# Contributing

Thanks for looking at MT5 Web Replicator and TradeMirror (the Copy Server and the MT5 EA).

## Proposing a change

1. Open an issue first for anything larger than a typo or a small fix, so we can agree on the
   approach. For the Copy Server and EA, the approved design is
   [`docs/design/0001-copy-core.md`](docs/design/0001-copy-core.md); changes that touch the
   protocol or copy semantics should reference the design section or scenario they affect.
2. Fork, create a branch, and open a pull request against `master`.
3. For a bug fix, include a regression test that fails before the fix and passes after it.
4. Keep pull requests focused. CI must be green before review.

## Contributor License Agreement

Before your first pull request can be merged you are asked to sign the
[CLA](CLA.md) by commenting on the pull request (the CLA bot explains how). You keep the copyright
in your contribution. The CLA lets the maintainer offer the project under its public license and
under separate commercial licenses.

## Running the tests

Copy Server (Python 3.12, [uv](https://docs.astral.sh/uv/)):

```bash
cd server
uv run ruff check .
uv run pytest                     # SQLite
# the same suite on Postgres, against a throwaway database:
createdb copycore_test && COPYCORE_TEST_DATABASE_URL=postgresql:///copycore_test uv run pytest; dropdb copycore_test
```

Rails app:

```bash
RAILS_ENV=test bin/rails db:create db:schema:load
bundle exec rspec --no-fail-fast
```

EA (needs MetaTrader 5; see [`ea/mt5/README.md`](ea/mt5/README.md)):

- Self-test: compile `TradeMirrorSelfTest.mq5` and run it in the Strategy Tester (hedging account,
  "Every tick", one day). A green run ends with `N passed, 0 failed`.
- EA/server contract: `server/tests/test_ea_contract.py` runs with the server suite.
- End-to-end harness (two demo terminals and a server): `uv run ea/mt5/e2e/run.py --env-file <env> --fast`.

Run the EA only on demo accounts when testing.

## Partnerships and commercial use

The code is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). You may
read, run, modify and share it for noncommercial purposes. Commercial use, including running it for
a business or as a service, needs a separate license. There is no commitment to accept any proposal.

To discuss collaboration or commercial use, open a GitHub issue titled "Partnerships and
collaboration" in this repository. Do not put credentials, account numbers or other private data in
an issue.
