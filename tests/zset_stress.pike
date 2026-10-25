//! ZSET + VMap correctness and stress.
//! Run: pike -M. tests/zset_stress.pike [host] [port] [members]
//! Uses db 15. Exit code = number of failures.

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
    int members;
    object c;
    object vm;
    array(mixed) top;
    int i;
    int t0;
    int dt;
    array(array(string)) batch;
    int b;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6379;
    members = argc > 3 ? (int)argv[3] : 10000;

    c = Valkey.Client(host, port);
    c->select(15);
    c->del("zb", "vm1");

    // ---- correctness ----
    check("zadd", c->zadd("zb", ([ "alice":100, "bob":200, "cid":150 ]), 0) == 3);
    check("zcard", c->zcard("zb") == 3);
    check("zrevrange", equal(c->zrevrange("zb", 0, -1), ({ "bob", "cid", "alice" })));
    check("zrange", equal(c->zrange("zb", 0, -1), ({ "alice", "cid", "bob" })));
    top = c->zrevrange("zb", 0, 1, 1);
    check("withscores", equal(top, ({ "bob", "200", "cid", "150" })));
    check("zscore", c->zscore("zb", "cid") == "150");
    check("zscore-miss", c->zscore("zb", "nobody") == 0);
    check("zrevrank", c->zrevrank("zb", "cid") == 1 && c->zrank("zb", "cid") == 1);
    check("zrank-miss", c->zrank("zb", "nobody") == 0);
    check("zincrby", c->zincrby("zb", 25, "alice") == "125");
    check("zcount", c->zcount("zb", "100", "200") == 3);
    check("zrangebyscore",
          equal(c->zrangebyscore("zb", "120", "200"), ({ "alice", "cid", "bob" })));
    check("zadd-nx", c->zadd("zb", ([ "bob":999 ]), ([ "nx":1 ])) == 0
          && c->zscore("zb", "bob") == "200");
    check("zadd-xx-miss", c->zadd("zb", ([ "ghost":1 ]), ([ "xx":1 ])) == 0);
    check("zrem", c->zrem("zb", "cid") == 1 && c->zcard("zb") == 2);
    c->zadd("zb", ([ "t1":1, "t2":2 ]), 0);
    check("zremrangebyrank", c->zremrangebyrank("zb", 0, 0) == 1);

    vm = VMap.Map(c, "vm1");
    check("vmap-set-get", vm->set("online", "7") == 1 && vm->get("online") == "7");
    check("vmap-miss", vm->get("nope") == 0);
    check("vmap-set-map", vm->set_map(([ "a":"1", "b":"2" ])) == 2);
    check("vmap-exists-size", vm->exists("a") == 1 && vm->size() == 3);
    check("vmap-incr", vm->incrby("online", 3) == 10);
    check("vmap-all", sizeof(vm->all()) == 3);
    check("vmap-keys", sizeof(vm->keys()) == 3);
    check("vmap-del-clear", vm->del("a", "b") == 2 && vm->clear() == 1
          && vm->size() == 0);

    // ---- stress: 10k-member board ----
    c->del("bigboard");
    batch = ({});
    for(i = 0; i < members; i++)
        batch += ({ ({ "ZADD", "bigboard", (string)(members - i),
                       "player:" + i }) });
    t0 = gethrtime();
    for(b = 0; b < sizeof(batch); b += 100)
        c->pipeline(batch[b..min(b + 99, sizeof(batch) - 1)]);
    dt = gethrtime() - t0;
    write("zadd-pipe:  %d members, %.1f members/sec\n",
          members, members / (dt / 1e6));
    check("board-size", c->zcard("bigboard") == members);

    t0 = gethrtime();
    for(i = 0; i < 1000; i++)
        top = c->zrevrange("bigboard", 0, 99);
    dt = gethrtime() - t0;
    write("top100:     1000 reads, %.1f reads/sec\n", 1000 / (dt / 1e6));
    check("top1", top[0] == "player:0" && top[1] == "player:1");

    t0 = gethrtime();
    for(i = 0; i < 1000; i++)
        c->zrevrank("bigboard", "player:" + (i * 7 % members));
    dt = gethrtime() - t0;
    write("revrank:    1000 lookups, %.1f lookups/sec\n", 1000 / (dt / 1e6));

    t0 = gethrtime();
    for(i = 0; i < 2000; i++)
        c->call("HINCRBY", "vmc", "hits", "1");
    dt = gethrtime() - t0;
    write("hincrby:    2000 ops, %.1f ops/sec\n", 2000 / (dt / 1e6));
    check("counter", c->call("HGET", "vmc", "hits") == "2000");

    c->del("zb", "vm1", "bigboard", "vmc");
    c->close();
    write(failures ? "RESULT: %d FAILURES\n" : "RESULT: ALL PASS\n", failures);
    return failures;
}
