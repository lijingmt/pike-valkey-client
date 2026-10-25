---
name: pike-valkey-client
description: Valkey/Redis client for Pike 9 (single-file Valkey.pmod, plus Json/VMap helpers). Use when connecting Pike code to Valkey/Redis, running its tests, or extending the client. Covers RESP usage, error model, persistence helpers, and the verified test suite.
---

# pike-valkey-client Skill

Pike 9 client for Valkey/Redis over RESP2. Valkey and Redis share the
wire protocol, so one client covers both. No dependencies beyond Pike 9
stdlib. MIT licensed.

## 30-second orientation

```sh
git clone https://github.com/lijingmt/pike-valkey-client.git
cd pike-valkey-client
./quickstart.sh   # checks Pike 9, ensures local Valkey on 6379, runs the demo
```

Repo layout:

```text
Valkey.pmod          # the client: class Client, call(), pipeline(), typed wrappers
Json.pmod            # generic Pike mapping <-> JSON (integer keys as "#n")
VMap.pmod            # hash-backed mapping facade for small shared tables
examples/basic.pike        # minimal end-to-end demo
examples/cache_aside.pike  # recommended pattern: hit / miss-backfill / Valkey-down passthrough
tests/smoke.pike           # 46 correctness + edge checks (needs live server, uses db 15)
tests/stress.pike          # sequential/pipeline/reconnect/BGSAVE throughput
tests/concurrent.pike      # N clients x M ops over per-thread connections
tests/persist.pike         # write / restart / verify persistence roundtrip
tests/persist_lib.pike     # persistence helpers (bgsave, config, ensure_persisted)
tests/json_stress.pike     # dumps/loads throughput + live JSON doc roundtrip
tests/zset_stress.pike     # ZSET + VMap correctness and stress
```

## Using the client (Pike)

```pike
object c = Valkey.Client("127.0.0.1", 6379);          // or ("valkey", 6379) in Docker
// object c = Valkey.Client(host, port, ([ "user":u, "pass":p, "db":n ]));
string v = c->get("k");                                // 0 when missing
c->set("k", "v", ([ "ex":60 ]));                       // opts: ex/px/nx/xx/get/keepttl
mixed r = c->call("SET", "k", "v", "EX", "60", "NX");  // generic escape hatch
array(mixed) out = c->pipeline(({ ({ "SET","a","1" }), ({ "GET","a" }) }));
```

Reply mapping: `+` -> string, `:` -> int, `$` -> string (nil -> `0`),
`*` -> array (nil -> `0`). Failed pipeline slots yield
`({"error", message})`; other slots are unaffected.

Error model (blocking I/O, no timeouts by design):

- Server errors (`-ERR`) raise catchable Pike errors; the connection
  stays usable and the next command works.
- A dead connection raises `Valkey: connection closed ...`; the socket
  is dropped and the next call auto-reconnects. Never auto-retry a
  failed command (non-idempotent writes must not run twice).
- Connection refused at connect time raises `Valkey: connection failed`.
- A stalled server blocks forever: wrap `call()` in a Pike `Thread`
  and `close()` from another thread to break out.

Key helpers: strings (`get/set/setex/setnx/del/exists/expire/ttl/incr/incrby/decr/mget/mset`),
hashes (`hset/hset_map/hget/hmget/hgetall/hdel/hexists/hlen/hincrby`),
lists (`lpush/rpush/lpop/rpop/llen/lrange/ltrim`),
sets (`sadd/srem/smembers/scard/sismember`),
sorted sets (`zadd` +NX/XX/GT/LT/CH, `zscore/zrank/zrevrank/zincrby/zcard/zcount`,
`zrange/zrevrange` +WITHSCORES, score/range trims),
misc (`type/dbsize/info/lastsave`),
persistence (`bgsave/bgrewriteaof/wait_bgsave_done/ensure_persisted/
persistence_info/config_get/config_set/shutdown`).

`VMap.Map(client, key)`: `get/set/set_map/all/del/exists/keys/size/
incrby/clear` over one hash key. For small shared tables only.

`Json.dumps(mapping)` / `Json.loads(string)`: integer keys become
`"#<n>"` (`307` -> `"#307"`, `"-5"` -> `"#-5"`); only those shapes decode
back to int. Everything else (nested maps/arrays, UTF-8, empty map vs
empty array, ints/floats) round-trips exactly.

## Design rules (do not break)

- Game archives stay authoritative on disk; Valkey is a speed layer.
  Cache-aside with source fallback is the recommended pattern
  (see `examples/cache_aside.pike`).
- One player profile = one Valkey string key; never split a profile
  across keys (profile layering itself lives outside this repo).
- Storage-affecting changes need a live-server test in `tests/`,
  following the existing file-per-area convention.
- Docs and code comments stay in English. `VERSION` constants follow
  semver independently from Pike releases; record changes in
  `CHANGELOG.md`.

## Verification

Every command below needs a live Valkey/Redis (the quickstart provides
one on 127.0.0.1:6379). A green suite is the release gate:

```sh
pike -M. tests/smoke.pike                                 # expect: RESULT: ALL PASS (46)
pike -M. tests/stress.pike 127.0.0.1 6379 3000
pike -M. tests/concurrent.pike 127.0.0.1 6379 1000 10     # expect: CONCURRENT: PASS
pike -M. tests/persist.pike 127.0.0.1 6380 write          # then restart server ...
pike -M. tests/persist.pike 127.0.0.1 6380 verify         # ... expect: ALL INTACT
pike -M. tests/persist_lib.pike 127.0.0.1 6380            # expect: ALL PASS (6)
pike -M. tests/json_stress.pike 127.0.0.1 6379 1000
pike -M. tests/zset_stress.pike 127.0.0.1 6379 10000      # expect: ALL PASS (29)
```

Record measured numbers in `README.md` when behavior changes them.
