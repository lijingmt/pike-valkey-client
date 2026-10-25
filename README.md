# pike-valkey-client

A minimal [Valkey](https://valkey.io/) / Redis client for
[Pike 9](https://pike.lysator.liu.se/), speaking RESP2 over TCP.
Valkey and Redis share the same wire protocol, so one client covers both.

- Single file: `Valkey.pmod`. Drop it on Pike's module path and use it.
- No dependencies beyond the Pike 9 standard library.
- MIT licensed. See [LICENSE](LICENSE).

## Requirements

- Pike 9 (tested on Pike v9.0 release 13).
- A Valkey or Redis server. Any recent version works (tested against
  `valkey/valkey:latest` in Docker).

Check yours:

```sh
pike --version
```

## 60-second quickstart (foolproof)

```sh
git clone https://github.com/lijingmt/pike-valkey-client.git
cd pike-valkey-client
./quickstart.sh            # macOS / Linux
```

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File quickstart.ps1
```

That one script checks Pike 9, reuses (or Docker-starts) a local Valkey
on `127.0.0.1:6379`, runs the demo, and prints what to try next.
Success looks like `ok: demo passed`.

Troubleshooting:

- `pike not found` → install Pike 9: https://pike.lysator.liu.se/download/
- `need Pike 9, found: ...` → the module only supports Pike 9.
- `nothing on 127.0.0.1:6379 and no docker` → start any Valkey/Redis
  on port 6379 yourself, then rerun. No data is touched except demo
  keys on a throwaway server.
- `demo did not complete` → the server accepted TCP but did not speak
  RESP; point the script at a real Valkey/Redis.

## Install

Copy the module somewhere on your module path, or point at this repo:

```sh
git clone https://github.com/lijingmt/pike-valkey-client.git
cd pike-valkey-client
pike -M. examples/basic.pike
```

## Quickstart

```pike
object c = Valkey.Client("127.0.0.1", 6379);

c->set("hello", "valkey");
write("get hello: %s\n", c->get("hello"));   // valkey

c->hset_map("user:1", ([ "name":"Ada", "score":"99" ]));
write("name: %s\n", c->hget("user:1", "name"));

c->rpush("jobs", "a", "b", "c");
write("jobs: %O\n", c->lrange("jobs", 0, -1));

// one round trip for three commands
write("pipe: %O\n", c->pipeline(({ ({ "SET", "p", "1" }),
                                   ({ "INCR", "p" }),
                                   ({ "GET", "p" }) })));
c->close();
```

With authentication and a database index:

```pike
object c = Valkey.Client("127.0.0.1", 6379,
                         ([ "user":"default",
                            "pass":"s3cret",
                            "db":2 ]));
```

There is also a generic escape hatch for any command not wrapped below:

```pike
mixed v = c->call("SET", "k", "v", "EX", "60", "NX");
```

## API

All calls block on the socket. Server errors and connection failures raise
Pike errors — catch them with `catch{}`, the connection stays usable
afterwards, and a dead connection is re-established on the next call.
There are no timeouts: do not use this client on a network where the
server may stall silently.

| Area | Methods |
|---|---|
| Connection | `Client(host?, port?, opts?)`, `close()`, `ping()`, `auth(password, username?)`, `select(db)` |
| Strings | `get`, `set` (+`ex`/`px`/`nx`/`xx`/`get`/`keepttl`), `setex`, `setnx`, `del`, `exists`, `expire`, `ttl`, `incr`, `incrby`, `decr`, `incrbyfloat`, `strlen`, `append`, `mget`, `mset` |
| Hashes | `hset`, `hset_map`, `hget`, `hmget`, `hgetall` (as mapping), `hdel`, `hexists`, `hlen` |
| Lists | `lpush`, `rpush`, `lpop`, `rpop`, `llen`, `lrange`, `ltrim` |
| Sets | `sadd`, `srem`, `smembers`, `scard`, `sismember` |
| Misc | `call(cmd, args...)`, `pipeline(cmds)`, `type`, `dbsize`, `info`, `lastsave` |
| Persistence | `bgsave`, `bgrewriteaof`, `wait_bgsave_done`, `ensure_persisted`, `persistence_info`, `config_get`, `config_set`, `shutdown` |
| JSON mapping | `Json.pmod`: `encode_mapping`/`decode_mapping`, `dumps`/`loads`; integer keys as `#n` |
| Sorted sets | `zadd` (+NX/XX/GT/LT/CH), `zscore`, `zrank`, `zrevrank`, `zincrby`, `zcard`, `zcount`, `zrange`, `zrevrange`, `zrangebyscore`, `zrevrangebyscore`, trims |
| Shared maps | `VMap.pmod`: hash-backed mapping facade for small shared tables |

Reply mapping: `+` → string, `:` → int, `$` → string (nil → `0`),
`*` → array (nil → `0`). A failed command inside `pipeline()` yields
`({"error", message})` in its slot; the other slots are unaffected.

`GET` on a missing key returns `0`. `HGETALL` on a missing key returns `([])`.
Values are byte strings: UTF-8, CRLF inside values, empty strings, and
megabyte values all round-trip.

## Using Valkey as a durable store (RDS-style)

Valkey with AOF + RDB snapshots on a Docker volume survives `docker kill`
(SIGKILL). Recipe used for the verified test below:

```sh
docker volume create valkey-data
docker run -d --name valkey-persist -p 6380:6379 \
  -v valkey-data:/data valkey/valkey:latest \
  valkey-server --appendonly yes --save "60 100" --loglevel warning
```

- `tests/persist.pike <host> <port> write` writes a mixed dataset
  (string, hash, list, set, counter) and runs `BGSAVE`.
- Kill/restart the container, then
  `tests/persist.pike <host> <port> verify` reads everything back.
- A key written *after* the snapshot also survived the SIGKILL restart,
  proving AOF replay (RDB alone could not have had it).
- For game use: the authoritative archive stays on disk with the game's
  own atomic save (live file + `.bak` + same-directory rename, never
  in-place overwrite). Valkey persistence only makes the speed layer
  survive restarts; if it ever disagrees with disk, disk wins and
  Valkey is refilled.

Operational notes: keep `appendonly yes`; schedule `BGSAVE` (or rely on
`save` points); back up `/data` (the volume); run `verify` after any
restore. This client exposes `lastsave()` and `info("persistence")` for
scripting those checks.

## Test report (local, 2026-10-25)

Environment: Apple Silicon Mac (Darwin 25.x), Docker Desktop,
`valkey/valkey:latest`, Pike v9.0 release 13, localhost TCP.
Nothing was mocked: every number below is a live server round trip.

**Smoke + edge cases** — `pike -M. tests/smoke.pike` → `RESULT: ALL PASS`
(46/46), covering: ping/echo, missing keys (`0`), empty-string values,
CRLF inside values, Unicode + emoji, 1 MB value round-trip, SET NX/XX/GET
semantics, SETEX+TTL, INCR family, DEL/EXISTS, MSET/MGET with gaps,
WRONGTYPE raising without breaking the connection (next command still
works), hashes/lists/sets incl. empty-container behavior, `INFO`,
pipelines with one failing slot, reconnect after `close()`, and
connection-refused raising a catchable error.

**Auth** — against a `--requirepass` server: no-auth raises, wrong
password raises, correct password (legacy and `user`+`pass` forms) works.

**Stress** — `pike -M. tests/stress.pike 127.0.0.1 6379 3000`:

| Phase | Result |
|---|---|
| PING round trips | 3,000 ops, ~5,380 ops/sec |
| SET+GET pairs | 6,000 ops, ~5,430 ops/sec |
| Pipelined SETs (100/batch) | 3,000 ops, ~221,500 ops/sec |
| Close+reconnect churn | 200 cycles, ~2,000 cycles/sec |
| Writes during BGSAVE | 500 ops, ~5,700 ops/sec, data verified intact |
| 1000 concurrent clients | 20,000 ops, ~14,760 ops/sec aggregate, 0 mismatches, 0 failed threads |
| Persistence helpers | `tests/persist_lib.pike` 6/6 pass; live `SHUTDOWN NOSAVE` + restart recovered serving |

(Single-shot throughput is Docker Desktop loopback bound; pipelining is
~41x. Numbers move with hardware — rerun on yours.)

**Persistence + crash recovery** — dataset written, `BGSAVE` completed
(`LASTSAVE` advanced), one extra key written post-snapshot,
`docker kill` (SIGKILL) + `docker start` → `tests/persist.pike … verify`
reports `ALL INTACT`, and the post-snapshot key came back, proving AOF
replay. `INFO persistence` after restart: `aof_enabled:1`,
`rdb_last_bgsave_status:ok`.

## Versioning

The module carries its own version, independent of Pike releases:

```pike
Valkey.VERSION;  // "1.0.0"
```

Bump it per [semver](https://semver.org/), note tested Pike versions in
[CHANGELOG.md](CHANGELOG.md), and tag releases (`v1.0.0`, …).

## Caching with fallback (recommended pattern)

Valkey is a speed layer, never the owner of data. `examples/cache_aside.pike`
shows the pattern all three paths verified live:

1. **Hit** → return from Valkey.
2. **Miss** → load from the source of truth (disk archive, DB),
   `SETEX` it back into Valkey, return.
3. **Valkey down** → load from source directly and return; no exception
   escapes, the game keeps serving with zero cache.

The game archive on disk stays authoritative; if Valkey ever disagrees
with it, disk wins and Valkey is refilled.

## Project philosophy

See [PHILOSOPHY.md](PHILOSOPHY.md): the infinite-loop engineer,
the monitoring engineer, and how this repo gets polished.

## License

MIT. See [LICENSE](LICENSE). The software is provided "as is",
without warranty of any kind.
