//! Persistence helpers. Run: pike -M. tests/persist_lib.pike [host] [port]
//! Needs a server you may CONFIG SET + BGSAVE on. Exit code = failures.

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
    mapping m;
    string hz;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6380;

    c = Valkey.Client(host, port);

    m = c->config_get("appendonly");
    check("config-get", sizeof(m) == 1 && m->appendonly == "yes");
    m = c->config_get("no-such-*");
    check("config-get-miss", sizeof(m) == 0);

    hz = c->config_get("hz")->hz;
    check("config-set-roundtrip",
          c->config_set("hz", hz) == "OK"
          && c->config_get("hz")->hz == hz);

    m = c->persistence_info();
    check("persistence-info",
          m->aof_enabled == "1" && (int)m->rdb_bgsave_in_progress == 0);

    check("ensure-persisted", c->ensure_persisted(60) == 1);
    check("lastsave-moved", c->lastsave() > 0);

    c->close();
    write(failures ? "RESULT: %d FAILURES\n" : "RESULT: ALL PASS\n", failures);
    return failures;
}
