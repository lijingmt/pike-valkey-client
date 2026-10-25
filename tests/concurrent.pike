//! Concurrent clients: N threads x M SET+GET pairs through the client.
//! Run: pike -M. tests/concurrent.pike [host] [port] [clients] [rounds]
//! Uses db 15. Exit code = number of threads with errors/mismatches.

mapping worker(int id, string host, int port, int rounds)
{
    mapping r;
    object c;
    int i;
    int t0;
    int dt;
    mixed err;
    string k;
    string want;
    r = ([ "ops":0, "mismatch":0, "error":"", "us":0 ]);
    err = catch {
        c = Valkey.Client(host, port);
        c->select(15);
        t0 = gethrtime();
        for(i = 0; i < rounds; i++) {
            k = "cc:" + id + ":" + i;
            want = "v" + i;
            c->set(k, want);
            if(c->get(k) != want) r->mismatch++;
            r->ops += 2;
        }
        dt = gethrtime() - t0;
        r->us = dt;
        c->close();
    };
    if(err) r->error = describe_error(err);
    return r;
}

int main(int argc, array(string) argv)
{
    string host;
    int port;
    int clients;
    int rounds;
    array(object) th;
    int i;
    int t0;
    int dt;
    int total_ops;
    int total_mismatch;
    int bad_threads;
    float tmin;
    float tmax;
    float tsum;
    mapping r;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6379;
    clients = argc > 3 ? (int)argv[3] : 1000;
    rounds = argc > 4 ? (int)argv[4] : 10;

    t0 = gethrtime();
    th = ({});
    for(i = 0; i < clients; i++)
        th += ({ Thread.Thread(worker, i, host, port, rounds) });
    total_ops = 0;
    total_mismatch = 0;
    bad_threads = 0;
    tmin = 1e30;
    tmax = 0.0;
    tsum = 0.0;
    for(i = 0; i < clients; i++) {
        float rate;
        r = th[i]->wait();
        total_ops += r->ops;
        total_mismatch += r->mismatch;
        if(sizeof(r->error)) {
            bad_threads++;
            if(bad_threads < 4)
                write("thread %d error: %s", i, r->error);
        }
        rate = r->ops / (r->us / 1e6);
        if(rate < tmin) tmin = rate;
        if(rate > tmax) tmax = rate;
        tsum += rate;
    }
    dt = gethrtime() - t0;
    write("clients:        %d\n", clients);
    write("ops/thread:     %d\n", rounds * 2);
    write("total ops:      %d\n", total_ops);
    write("aggregate:      %.1f ops/sec (wall %.1fs)\n",
          total_ops / (dt / 1e6), dt / 1e6);
    write("per-thread:     min %.1f, max %.1f, avg %.1f ops/sec\n",
          tmin, tmax, tsum / clients);
    write("mismatches:     %d\n", total_mismatch);
    write("failed threads: %d\n", bad_threads);
    write(bad_threads || total_mismatch ? "CONCURRENT: FAIL\n" : "CONCURRENT: PASS\n");
    return (bad_threads || total_mismatch) ? 1 : 0;
}
