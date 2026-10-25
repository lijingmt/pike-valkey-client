//! Smoke + edge cases against a live Valkey (default 127.0.0.1:6379).
//! Run: pike -M. tests/smoke.pike [host] [port]
//! Uses db 15 and flushes it. Exit code = number of failures.

int failures = 0;

void check(string name, int cond)
{
    if(cond) {
        write("ok   %s\n", name);
    } else {
        failures++;
        write("FAIL %s\n", name);
    }
}

int main(int argc, array(string) argv)
{
    string host;
    int port;
    object c;
    mixed e;
    mixed v;
    mapping m;
    array(mixed) a;
    string big;
    string uni;
    string crlf;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6379;

    c = Valkey.Client(host, port);
    check("ping", c->ping() == "PONG");
    check("ping-echo", c->ping("hi") == "hi");
    c->select(15);
    c->call("FLUSHDB");

    // strings + boundaries
    check("set", c->set("k", "v") == "OK");
    check("get", c->get("k") == "v");
    check("get-missing", c->get("no-such-key") == 0);
    check("empty-value", c->set("e", "") == "OK" && c->get("e") == "");
    crlf = "a\r\nb\nc\rd";
    check("crlf-in-value", c->set("c", crlf) == "OK" && c->get("c") == crlf);
    uni = "中文Valkey🎉";
    check("unicode", c->set("u", uni) == "OK" && c->get("u") == uni);
    big = "x" * (1024 * 1024);
    check("1MB-value", c->set("big", big) == "OK" && c->get("big") == big);
    check("set-nx-new", c->set("nx", "1", ([ "nx":1 ])) == "OK");
    check("set-nx-refused", c->set("nx", "2", ([ "nx":1 ])) == 0);
    check("set-xx-miss", c->set("xx-miss", "1", ([ "xx":1 ])) == 0);
    check("setex-ttl", c->setex("t", 100, "v") == "OK"
          && c->ttl("t") > 0 && c->ttl("t") <= 100);
    check("set-get-opt", c->set("g", "new", ([ "get":1 ])) == 0
          && c->set("g", "new2", ([ "get":1 ])) == "new");
    check("incr-fresh", c->incr("cnt") == 1 && c->incrby("cnt", 41) == 42
          && c->decr("cnt") == 41);
    check("del-exists", c->set("d", "1") == "OK" && c->exists("d") == 1
          && c->del("d") == 1 && c->exists("d") == 0);
    v = c->mset(([ "m1":"a", "m2":"b" ]));
    a = c->mget(({ "m1", "m2", "m-miss" }));
    check("mset-mget", v == "OK" && equal(a, ({ "a", "b", 0 })));

    // wrong type must raise, not hang or corrupt the stream
    c->rpush("alist", "x");
    e = catch { c->get("alist"); };
    check("wrongtype-raises", !!e);
    check("stream-alive-after-error", c->ping() == "PONG");

    // hashes
    check("hset", c->hset("h", "f", "v") == 1);
    check("hset-map", c->hset_map("h", ([ "a":"1", "b":"2" ])) == 2);
    check("hget", c->hget("h", "f") == "v");
    check("hget-miss", c->hget("h", "nope") == 0);
    m = c->hgetall("h");
    check("hgetall", sizeof(m) == 3 && m->a == "1");
    check("hgetall-miss", sizeof(c->hgetall("h-miss")) == 0);
    check("hexists-hlen", c->hexists("h", "f") == 1 && c->hlen("h") == 3);
    check("hdel", c->hdel("h", "a", "b") == 2 && c->hlen("h") == 1);

    // lists
    c->del("lst");
    check("rpush", c->rpush("lst", "a", "b", "c") == 3);
    check("lpush", c->lpush("lst", "z") == 4);
    check("lrange", equal(c->lrange("lst", 0, -1), ({ "z", "a", "b", "c" })));
    check("llen", c->llen("lst") == 4);
    check("lpop-rpop", c->lpop("lst") == "z" && c->rpop("lst") == "c");
    check("lpop-miss", c->lpop("lst-miss") == 0);
    check("ltrim", c->ltrim("lst", 0, 0) == "OK" && c->llen("lst") == 1);

    // sets
    c->del("sset");
    check("sadd", c->sadd("sset", "a", "b", "a") == 2);
    check("scard", c->scard("sset") == 2);
    check("sismember", c->sismember("sset", "a") == 1
          && c->sismember("sset", "z") == 0);
    check("smembers", sizeof(c->smembers("sset")) == 2);
    check("srem", c->srem("sset", "a") == 1 && c->scard("sset") == 1);

    // misc
    check("type", c->type("lst") == "list");
    check("dbsize", c->dbsize() >= 1);
    check("info", search(c->info("server"), "valkey_version") >= 0
          || search(c->info("server"), "redis_version") >= 0);

    // pipeline incl. one failing command
    a = c->pipeline(({ ({ "SET", "p1", "1" }),
                         ({ "GET", "alist" }),
                         ({ "GET", "p1" }) }));
    check("pipeline", a[0] == "OK" && a[2] == "1"
          && arrayp(a[1]) && a[1][0] == "error");

    // reconnect after close
    c->close();
    check("reconnect", c->ping() == "PONG");

    // connection failure must raise fast-ish, not hang forever
    object bad = Valkey.Client(host, 6398);
    e = catch { bad->ping(); };
    check("conn-refused-raises", !!e
          && search(describe_error(e), "connection failed") >= 0);

    c->call("FLUSHDB");
    c->close();
    write(failures ? "RESULT: %d FAILURES\n" : "RESULT: ALL PASS\n", failures);
    return failures;
}
