//! Persistence check: Valkey as a durable store.
//! Usage:
//!   pike -M. tests/persist.pike <host> <port> write    # writes dataset + BGSAVE
//!   # ... restart or kill the server ...
//!   pike -M. tests/persist.pike <host> <port> verify   # reads everything back
//! Exit code = number of mismatches.

int main(int argc, array(string) argv)
{
    string host;
    int port;
    string mode;
    object c;
    int bad;
    int i;
    if(argc < 4) {
        write("usage: persist.pike <host> <port> write|verify\n");
        return 2;
    }
    host = argv[1];
    port = (int)argv[2];
    mode = argv[3];
    c = Valkey.Client(host, port);
    bad = 0;

    if(mode == "write") {
        c->set("rds:string", "durable-value-1");
        c->hset_map("rds:hash", ([ "f1":"v1", "f2":"v2", "f3":"v3" ]));
        c->rpush("rds:list", "a", "b", "c");
        c->sadd("rds:set", "x", "y");
        c->set("rds:counter", "41");
        c->incrby("rds:counter", 1);
        write("lastsave-before=%d\n", c->lastsave());
        write("bgsave=%s\n", c->call("BGSAVE"));
        // wait until the background save finishes
        for(i = 0; i < 100; i++) {
            string info = c->info("persistence");
            if(search(info, "rdb_bgsave_in_progress:0") >= 0) break;
            sleep(1);
        }
        write("lastsave-after=%d\n", c->lastsave());
        write("WRITE DONE (kill -9 / docker kill the server now, then verify)\n");
    } else if(mode == "verify") {
        if(c->get("rds:string") != "durable-value-1") { bad++; write("FAIL string\n"); }
        if(!equal(c->hgetall("rds:hash"), ([ "f1":"v1", "f2":"v2", "f3":"v3" ]))) { bad++; write("FAIL hash\n"); }
        if(!equal(c->lrange("rds:list", 0, -1), ({ "a", "b", "c" }))) { bad++; write("FAIL list\n"); }
        if(c->scard("rds:set") != 2) { bad++; write("FAIL set\n"); }
        if(c->get("rds:counter") != "42") { bad++; write("FAIL counter\n"); }
        write(bad ? "VERIFY: %d MISMATCHES\n" : "VERIFY: ALL INTACT\n", bad);
    } else {
        write("unknown mode\n");
        return 2;
    }
    c->close();
    return bad;
}
