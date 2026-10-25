//? Basic usage. Run: pike -M. examples/basic.pike [host] [port]
//? SPDX-License-Identifier: MIT

int main(int argc, array(string) argv)
{
    string host;
    int port;
    object c;
    host = argc > 1 ? argv[1] : "127.0.0.1";
    port = argc > 2 ? (int)argv[2] : 6379;

    c = Valkey.Client(host, port);
    write("ping: %s\n", c->ping());

    c->set("hello", "valkey");
    write("get hello: %s\n", c->get("hello"));

    c->hset_map("user:1", ([ "name":"Ada", "score":"99" ]));
    write("user:1 name: %s\n", c->hget("user:1", "name"));

    c->rpush("jobs", "a", "b", "c");
    write("jobs: %O\n", c->lrange("jobs", 0, -1));

    // one round trip for three commands
    write("pipeline: %O\n", c->pipeline(({ ({ "SET", "p", "1" }),
                                           ({ "INCR", "p" }),
                                           ({ "GET", "p" }) })));

    // errors are catchable, the connection stays usable
    mixed e = catch { c->get("jobs"); };  // WRONGTYPE: jobs is a list
    write("wrongtype caught: %s", e ? "yes\n" : "no\n");
    write("still alive: %s\n", c->ping());

    c->close();
    return 0;
}
