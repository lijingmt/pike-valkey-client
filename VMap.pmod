//! Valkey-backed mapping facade: one hash key behaves like a Pike
//! mapping for small shared tables (online counters, presence flags,
//! per-scene tallies). Every operation is one Valkey round trip;
//! do not use it for large scans -- fetch once with all() instead.
//!
//! SPDX-License-Identifier: MIT

//! Module version, independent from Pike releases. Follow semver.
constant VERSION = "1.4.0";

//! A mapping-like view over one hash key.
class Map
{
    object client;
    string key;

    protected void create(object _client, string _key)
    {
        client = _client;
        key = _key;
    }

    string|zero get(string field)
    {
        return client->hget(key, field);
    }

    int set(string field, string val)
    {
        return client->hset(key, field, val);
    }

    int set_map(mapping vals)
    {
        return client->hset_map(key, vals);
    }

    mapping all()
    {
        return client->hgetall(key);
    }

    int del(string ... fields)
    {
        return client->hdel(key, @fields);
    }

    int exists(string field)
    {
        return client->hexists(key, field);
    }

    array(mixed) keys()
    {
        array(mixed) raw;
        raw = client->call("HKEYS", key);
        return raw || ({});
    }

    int size()
    {
        return client->hlen(key);
    }

    int incrby(string field, int n)
    {
        return client->hincrby(key, field, n);
    }

    //! Drop the whole map.
    int clear()
    {
        return client->del(key);
    }
}
