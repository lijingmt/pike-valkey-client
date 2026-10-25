//! Valkey / Redis client for Pike 9.
//!
//! Minimal RESP2 client over TCP. Valkey and Redis speak the same wire
//! protocol, so this module works for both.
//!
//! SPDX-License-Identifier: MIT

//! Module version (independent from Pike releases). Follow semver.
constant VERSION = "1.0.0";

//! One connection. Create with Valkey.Client(), then call commands.
//! All calls block on the socket (no timeouts); server errors and
//! connection failures raise errors catchable with catch{}.
class Client
{
    string host = "127.0.0.1";
    int port = 6379;
    string user;
    string pass;
    int db = -1;

    protected object sock;
    protected string rbuf = "";

    //! Create a client. Does not connect yet (lazy connect on first call).
    //! opts may hold "user", "pass" and "db".
    protected void create(string|void _host, int|void _port, mapping|void opts)
    {
        mapping o;
        if(_host) host = _host;
        if(_port) port = _port;
        o = opts || ([]);
        if(o->user) user = o->user;
        if(o->pass) pass = o->pass;
        if(!zero_type(o->db)) db = o->db;
    }

    //! Close the connection. The client reconnects on the next call.
    void close()
    {
        _drop();
    }

    protected void _drop()
    {
        mixed err;
        if(sock) {
            err = catch { sock->close(); };
        }
        sock = 0;
        rbuf = "";
    }

    protected void _ensure()
    {
        mixed err;
        int ok;
        if(sock) return;
        sock = Stdio.File();
        ok = 0;
        err = catch { ok = sock->connect(host, port); };
        if(err || !ok) {
            _drop();
            error("Valkey: connection failed to " + host + ":" + port + ".\n");
        }
        if(pass) {
            if(user) call("AUTH", user, pass);
            else call("AUTH", pass);
        }
        if(db >= 0) call("SELECT", (string)db);
    }

    //! Take exactly n bytes for the current reply. Only called when the
    //! protocol guarantees those bytes are on the way, so this always
    //! terminates: either the bytes arrive or the server has closed the
    //! connection and we raise an error.
    protected string _take(int n)
    {
        string chunk;
        while(sizeof(rbuf) < n) {
            chunk = sock->read(65536, 1);
            if(!chunk || !sizeof(chunk))
                error("Valkey: connection closed by server.\n");
            rbuf += chunk;
        }
        string out = rbuf[..n-1];
        if(sizeof(rbuf) == n) rbuf = "";
        else rbuf = rbuf[n..];
        return out;
    }

    protected string _read_line()
    {
        string line;
        string chunk;
        int pos;
        while(1) {
            pos = search(rbuf, "\n");
            if(pos < 0) {
                chunk = sock->read(65536, 1);
                if(!chunk || !sizeof(chunk))
                    error("Valkey: connection closed by server.\n");
                rbuf += chunk;
                continue;
            }
            if(pos == 0) line = "";
            else line = rbuf[..pos-1];
            if(pos + 1 < sizeof(rbuf)) rbuf = rbuf[pos+1..];
            else rbuf = "";
            if(sizeof(line) && line[-1] == '\r')
                line = line[..<1];
            return line;
        }
    }

    protected string _read_n(int n)
    {
        string data;
        data = _take(n + 2);
        if(n == 0) return "";
        return data[..n-1];
    }

    //! Parse one RESP2 reply. Errors from the server raise Pike errors.
    protected mixed _parse()
    {
        string line;
        string data;
        array(mixed) arr;
        int n;
        int i;
        line = _read_line();
        if(!sizeof(line))
            error("Valkey: connection sent empty reply.\n");
        int t = line[0];
        if(t == '+') return line[1..];
        if(t == '-') error("Valkey: " + line[1..] + "\n");
        if(t == ':') return (int)line[1..];
        if(t == '$') {
            if(!sscanf(line[1..], "%d", n))
                error("Valkey: connection sent bad bulk length.\n");
            if(n == -1) return 0;
            data = _read_n(n);
            return data;
        }
        if(t == '*') {
            if(!sscanf(line[1..], "%d", n))
                error("Valkey: connection sent bad array length.\n");
            if(n == -1) return 0;
            arr = ({});
            for(i = 0; i < n; i++) arr += ({ _parse() });
            return arr;
        }
        error("Valkey: connection sent unknown reply type.\n");
    }

    protected string _encode(array(string) parts)
    {
        string out;
        int i;
        out = "*" + sizeof(parts) + "\r\n";
        for(i = 0; i < sizeof(parts); i++)
            out += "$" + sizeof(parts[i]) + "\r\n" + parts[i] + "\r\n";
        return out;
    }

    //! Send any command. Returns string, int, array or 0 (nil reply).
    //! Example: client->call("SET", "k", "v");
    mixed call(string cmd, string ... args)
    {
        mixed err;
        mixed res;
        err = catch {
            _ensure();
            sock->write(_encode(({ cmd }) + args));
            res = _parse();
        };
        if(err) {
            string msg = describe_error(err);
            if(search(msg, "Valkey: connection") == 0) _drop();
            throw(err);
        }
        return res;
    }

    //! Send several commands at once, read all replies in order.
    //! Each entry is an array of command words. A failed command
    //! yields ({"error", message}) in its slot, others are unaffected.
    array(mixed) pipeline(array(array(string)) cmds)
    {
        string out;
        array(mixed) res;
        int i;
        mixed err;
        mixed one;
        out = "";
        for(i = 0; i < sizeof(cmds); i++) out += _encode(cmds[i]);
        res = ({});
        err = catch {
            _ensure();
            sock->write(out);
            for(i = 0; i < sizeof(cmds); i++) {
                mixed slot_err;
                slot_err = catch { one = _parse(); };
                if(slot_err) res += ({ ({ "error", describe_error(slot_err) }) });
                else res += ({ one });
            }
        };
        if(err) {
            string msg = describe_error(err);
            if(search(msg, "Valkey: connection") == 0) _drop();
            throw(err);
        }
        return res;
    }

    // ---- connection ----

    string ping(string|void msg)
    {
        if(msg) return call("PING", msg);
        return call("PING");
    }

    string auth(string password, string|void username)
    {
        if(username) return call("AUTH", username, password);
        return call("AUTH", password);
    }

    string select(int db)
    {
        return call("SELECT", (string)db);
    }

    // ---- strings ----

    //! GET. Returns the value, or 0 when the key is missing.
    string|zero get(string key)
    {
        return call("GET", key);
    }

    //! SET with optional mapping: ([ "ex":60 ]) ([ "px":5000 ])
    //! ([ "nx":1 ]) ([ "xx":1 ]) ([ "get":1 ]) ([ "keepttl":1 ]).
    //! Returns "OK", 0 (NX/XX refused) or the old value (GET).
    mixed set(string key, string val, mapping|void opts)
    {
        mapping o;
        array(string) args;
        o = opts || ([]);
        args = ({ key, val });
        if(o->ex) args += ({ "EX", (string)o->ex });
        if(o->px) args += ({ "PX", (string)o->px });
        if(o->nx) args += ({ "NX" });
        if(o->xx) args += ({ "XX" });
        if(o->get) args += ({ "GET" });
        if(o->keepttl) args += ({ "KEEPTTL" });
        return call("SET", @args);
    }

    string setex(string key, int seconds, string val)
    {
        return call("SETEX", key, (string)seconds, val);
    }

    int setnx(string key, string val)
    {
        return call("SETNX", key, val);
    }

    int del(string ... keys)
    {
        return call("DEL", @keys);
    }

    int exists(string ... keys)
    {
        return call("EXISTS", @keys);
    }

    int expire(string key, int seconds)
    {
        return call("EXPIRE", key, (string)seconds);
    }

    int ttl(string key)
    {
        return call("TTL", key);
    }

    int incr(string key)
    {
        return call("INCR", key);
    }

    int incrby(string key, int n)
    {
        return call("INCRBY", key, (string)n);
    }

    int decr(string key)
    {
        return call("DECR", key);
    }

    string incrbyfloat(string key, float n)
    {
        return call("INCRBYFLOAT", key, (string)n);
    }

    int strlen(string key)
    {
        return call("STRLEN", key);
    }

    int append(string key, string val)
    {
        return call("APPEND", key, val);
    }

    array(mixed) mget(array(string) keys)
    {
        return call("MGET", @keys);
    }

    string mset(mapping vals)
    {
        array(string) keys;
        array(string) args;
        int i;
        keys = indices(vals);
        args = ({});
        for(i = 0; i < sizeof(keys); i++)
            args += ({ keys[i], vals[keys[i]] });
        return call("MSET", @args);
    }

    // ---- hashes ----

    int hset(string key, string field, string val)
    {
        return call("HSET", key, field, val);
    }

    int hset_map(string key, mapping vals)
    {
        array(string) fields;
        array(string) args;
        int i;
        fields = indices(vals);
        args = ({ key });
        for(i = 0; i < sizeof(fields); i++)
            args += ({ fields[i], vals[fields[i]] });
        return call("HSET", @args);
    }

    string|zero hget(string key, string field)
    {
        return call("HGET", key, field);
    }

    array(mixed) hmget(string key, array(string) fields)
    {
        return call("HMGET", key, @fields);
    }

    //! HGETALL as a mapping. Missing key gives ([]).
    mapping hgetall(string key)
    {
        array(mixed) raw;
        mapping out;
        int i;
        raw = call("HGETALL", key);
        out = ([]);
        if(!raw) return out;
        for(i = 0; i + 1 < sizeof(raw); i += 2)
            out[raw[i]] = raw[i+1];
        return out;
    }

    int hdel(string key, string ... fields)
    {
        return call("HDEL", key, @fields);
    }

    int hexists(string key, string field)
    {
        return call("HEXISTS", key, field);
    }

    int hlen(string key)
    {
        return call("HLEN", key);
    }

    // ---- lists ----

    int lpush(string key, string ... vals)
    {
        return call("LPUSH", key, @vals);
    }

    int rpush(string key, string ... vals)
    {
        return call("RPUSH", key, @vals);
    }

    string|zero lpop(string key)
    {
        return call("LPOP", key);
    }

    string|zero rpop(string key)
    {
        return call("RPOP", key);
    }

    int llen(string key)
    {
        return call("LLEN", key);
    }

    array(mixed) lrange(string key, int start, int stop)
    {
        return call("LRANGE", key, (string)start, (string)stop);
    }

    string ltrim(string key, int start, int stop)
    {
        return call("LTRIM", key, (string)start, (string)stop);
    }

    // ---- sets ----

    int sadd(string key, string ... members)
    {
        return call("SADD", key, @members);
    }

    int srem(string key, string ... members)
    {
        return call("SREM", key, @members);
    }

    array(mixed) smembers(string key)
    {
        return call("SMEMBERS", key);
    }

    int scard(string key)
    {
        return call("SCARD", key);
    }

    int sismember(string key, string member)
    {
        return call("SISMEMBER", key, member);
    }

    // ---- misc ----

    string type(string key)
    {
        return call("TYPE", key);
    }

    int dbsize()
    {
        return call("DBSIZE");
    }

    string info(string|void section)
    {
        if(section) return call("INFO", section);
        return call("INFO");
    }

    int lastsave()
    {
        return call("LASTSAVE");
    }
}
