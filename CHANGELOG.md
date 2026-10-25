# CHANGELOG

Module versions are independent from Pike releases (semver).

## Unreleased

- `examples/cache_aside.pike`: cache-aside with source fallback
  (hit / miss-backfill / Valkey-down passthrough), all paths verified.

## 1.2.0 — 2026-10-25

- Persistence helpers: `bgsave`, `bgrewriteaof`, `wait_bgsave_done`,
  `ensure_persisted` (snapshot + verify LASTSAVE moved), `persistence_info`,
  `config_get`/`config_set`, graceful `shutdown`.
- New `tests/persist_lib.pike` (6/6 pass) and live `SHUTDOWN NOSAVE` +
  restart recovery verified.
- `Valkey.VERSION` bumped to 1.2.0.

## 1.1.0 — 2026-10-25

- 1000-concurrency test (`tests/concurrent.pike`): N threads × M SET+GET
  pairs over per-thread connections, aggregate + per-thread throughput.
- `Valkey.VERSION` bumped to 1.1.0.

## 1.0.0 — 2026-10-25

- First release: RESP2 client for Valkey/Redis on Pike 9.
- Strings, hashes, lists, sets, key commands, `call()` and `pipeline()`.
- Lazy connect, AUTH/SELECT, auto-reconnect on the next call.
