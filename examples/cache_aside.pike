//? Cache-aside with fallback. Run: pike -M. examples/cache_aside.pike
//?
//? Pattern (use it against any source of truth: disk archives, DB, ...):
//?   1. Try Valkey. Hit -> return.
//?   2. Miss -> load from source, SETEX into Valkey, return.
//?   3. Valkey down -> load from source directly, return (no caching).
//? The game archive on disk is always the fallback. Valkey never owns data.
//?
//? SPDX-License-Identifier: MIT

// Stand-in for the real source of truth (disk archive, DB, ...).
// Replace the body with your loader; keep the signature.
string load_from_source(string key)
{
    return "source-value-for:" + key;
}

string cached_get(object c, string key, int ttl)
{
    mixed err;
    string|zero v;
    err = catch { v = c->get(key); };
    if(err) return load_from_source(key);  // Valkey down: no cache, still serve
    if(v) return v;                        // cache hit
    v = load_from_source(key);             // cache miss: load ...
    err = catch { c->setex(key, ttl, v); };// ... and backfill (best effort)
    return v;
}

int main()
{
    object c;
    string k;
    k = "demo:player:001";

    // 1) healthy Valkey: miss -> source -> hit
    c = Valkey.Client("127.0.0.1", 6379);
    c->del(k);
    write("miss:  %s\n", cached_get(c, k, 60));
    write("hit:   %s\n", cached_get(c, k, 60));
    c->close();

    // 2) Valkey down: straight to source, no exception escapes
    c = Valkey.Client("127.0.0.1", 6398);
    write("down:  %s\n", cached_get(c, k, 60));

    write("CACHE-ASIDE OK\n");
    return 0;
}
