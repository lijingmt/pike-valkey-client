# CHANGELOG

Module versions are independent from Pike releases (semver).

## 1.1.0 — 2026-10-25

- 1000-concurrency test (`tests/concurrent.pike`): N threads × M SET+GET
  pairs over per-thread connections, aggregate + per-thread throughput.
- `Valkey.VERSION` bumped to 1.1.0.

## 1.0.0 — 2026-10-25

- First release: RESP2 client for Valkey/Redis on Pike 9.
- Strings, hashes, lists, sets, key commands, `call()` and `pipeline()`.
- Lazy connect, AUTH/SELECT, auto-reconnect on the next call.
