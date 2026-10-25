//! Throughput stress. Run: pike -M. tests/stress.pike [host] [port] [rounds]
//! Uses db 15. Prints ops/sec per phase. Any error aborts the run.

int main(int argc, array(string) argv)
{
    string host;
    int port;
    int rounds;
    object c;
    int i;
    int t0;
    int dt;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6379;
    rounds = argc > 3 ? (int)argv[3] : 2000;

    c = Valkey.Client(host, port);
    c->select(15);
    c->call("FLUSHDB");

    // phase 1: ping round trips
    t0 = gethrtime();
    for(i = 0; i < rounds; i++) c->ping();
    dt = gethrtime() - t0;
    write("ping:        %d ops, %.1f ops/sec\n",
          rounds, rounds / (dt / 1e6));

    // phase 2: set+get pairs
    t0 = gethrtime();
    for(i = 0; i < rounds; i++) {
        c->set("s:" + i, "v:" + i);
        if(c->get("s:" + i) != "v:" + i)
            error("mismatch at s:" + i + "\n");
    }
    dt = gethrtime() - t0;
    write("set+get:     %d ops, %.1f ops/sec\n",
          rounds * 2, rounds * 2 / (dt / 1e6));

    // phase 3: pipelined sets, 100 per batch
    int batches = rounds / 100;
    array(array(string)) batch;
    int b;
    int j;
    t0 = gethrtime();
    for(b = 0; b < batches; b++) {
        batch = ({});
        for(j = 0; j < 100; j++)
            batch += ({ ({ "SET", "p:" + b + ":" + j, "x" }) });
        c->pipeline(batch);
    }
    dt = gethrtime() - t0;
    write("pipeline:    %d ops, %.1f ops/sec\n",
          batches * 100, batches * 100 / (dt / 1e6));

    // phase 4: connection churn (close + reconnect each time)
    t0 = gethrtime();
    for(i = 0; i < 200; i++) {
        c->close();
        c->ping();
    }
    dt = gethrtime() - t0;
    write("reconnect:   200 cycles, %.1f cycles/sec\n", 200 / (dt / 1e6));

    // phase 5: writes during BGSAVE (critical state), then verify
    c->call("BGSAVE");
    t0 = gethrtime();
    for(i = 0; i < 500; i++) c->set("bg:" + i, "v");
    dt = gethrtime() - t0;
    write("write-during-bgsave: 500 ops, %.1f ops/sec\n", 500 / (dt / 1e6));
    int bad = 0;
    for(i = 0; i < 500; i++)
        if(c->get("bg:" + i) != "v") bad++;
    write("bgsave-verify: %s\n", bad ? "MISMATCH " + bad : "all intact");

    c->call("FLUSHDB");
    c->close();
    write("STRESS DONE\n");
    return 0;
}
