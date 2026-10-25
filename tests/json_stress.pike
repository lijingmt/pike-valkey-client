//! JSON path stress: dumps/loads throughput plus live Valkey roundtrips.
//! Run: pike -M. tests/json_stress.pike [host] [port] [docs]
//! Uses db 15. Exit code = number of mismatches.

mapping make_doc(int id)
{
    return ([
        "userid": "xd01test" + id,
        "name": "测试玩家🎮" + id,
        "lvl": 55 + (id % 100),
        "plus": ([ "daily": ([ "mon":11, "day":20, "honer_map":([]) ]),
                   "random_rcd":0, "blacklist":([]) ]),
        "taskd": ([ "Cont": ([ 307:(["status":id % 3]),
                               308:(["start_time":1790000000 + id]) ]) ]),
        "tags": ({ "a", "b", "c" }),
        "bag": ({}),
        "attr": ([]),
    ]);
}

int main(int argc, array(string) argv)
{
    string host;
    int port;
    int ndocs;
    object c;
    int i;
    int t0;
    int dt;
    mapping doc;
    string j;
    array(string) keys;
    array(array(string)) batch;
    array(mixed) got;
    int bad;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6379;
    ndocs = argc > 3 ? (int)argv[3] : 1000;

    doc = make_doc(0);
    t0 = gethrtime();
    for(i = 0; i < 2000; i++) j = Json.dumps(doc);
    dt = gethrtime() - t0;
    write("dumps:      2000 docs, %.1f docs/sec\n", 2000 / (dt / 1e6));

    t0 = gethrtime();
    for(i = 0; i < 2000; i++) Json.loads(j);
    dt = gethrtime() - t0;
    write("loads:      2000 docs, %.1f docs/sec\n", 2000 / (dt / 1e6));

    c = Valkey.Client(host, port);
    c->select(15);
    keys = ({});
    batch = ({});
    for(i = 0; i < ndocs; i++) {
        keys += ({ "jsondoc:" + i });
        batch += ({ ({ "SET", "jsondoc:" + i, Json.dumps(make_doc(i)) }) });
    }
    t0 = gethrtime();
    for(i = 0; i < sizeof(batch); i += 50)
        c->pipeline(batch[i..min(i + 49, sizeof(batch) - 1)]);
    dt = gethrtime() - t0;
    write("live SET:   %d docs, %.1f docs/sec\n", ndocs, ndocs / (dt / 1e6));

    batch = ({});
    for(i = 0; i < ndocs; i++)
        batch += ({ ({ "GET", "jsondoc:" + i }) });
    t0 = gethrtime();
    got = ({});
    for(i = 0; i < sizeof(batch); i += 50)
        got += c->pipeline(batch[i..min(i + 49, sizeof(batch) - 1)]);
    dt = gethrtime() - t0;
    write("live GET:   %d docs, %.1f docs/sec\n", ndocs, ndocs / (dt / 1e6));

    bad = 0;
    for(i = 0; i < ndocs; i += 37) {
        mapping want;
        mapping live;
        want = make_doc(i);
        live = Json.loads(got[i]);
        if(!equal(live, want)) {
            bad++;
            if(bad < 4) write("MISMATCH doc %d\n", i);
        }
    }
    write("verify:     %s (sampled every 37th)\n",
          bad ? bad + " MISMATCHES" : "all intact");
    c->call("FLUSHDB");
    c->close();
    write("JSON-STRESS DONE\n");
    return bad ? 1 : 0;
}
