//! Generic Pike mapping <-> JSON conversion.
//!
//! Standards.JSON cannot encode mappings with non-string keys, so this
//! module pre-converts Pike integer keys to JSON "#<n>" keys ("307"
//! would collide with real string keys, so plain numbers are never
//! used). Integer-like strings that YOU stored stay strings: only
//! "#<digits>" (optional leading "-") decodes back to int. A genuine
//! "#123" string key would also decode as int 123 -- avoid such keys.
//!
//! Only JSON-compatible values are allowed: mappings, arrays, strings,
//! ints and floats. Anything else raises a clear error.
//!
//! SPDX-License-Identifier: MIT

//! Module version, independent from Pike releases. Follow semver.
constant VERSION = "1.3.0";

//! Convert integer mapping keys to "#n" strings, recursively.
mapping encode_mapping(mapping data)
{
    mapping out;
    array(mixed) keys;
    int i;
    out = ([]);
    keys = indices(data);
    for(i = 0; i < sizeof(keys); i++) {
        mixed k = keys[i];
        mixed v = data[k];
        string sk;
        if(intp(k)) sk = "#" + k;
        else if(stringp(k)) sk = k;
        else error("Json: unsupported key type, only int/string allowed.\n");
        out[sk] = encode_value(v);
    }
    return out;
}

protected mixed encode_value(mixed v)
{
    if(mappingp(v)) return encode_mapping(v);
    if(arrayp(v)) {
        array(mixed) out;
        int i;
        out = ({});
        for(i = 0; i < sizeof(v); i++)
            out += ({ encode_value(v[i]) });
        return out;
    }
    if(stringp(v) || intp(v) || floatp(v)) return v;
    error("Json: unsupported value type, only mapping/array/string/int/float allowed.\n");
}

//! Reverse of encode_mapping: "#n" string keys become ints.
mapping decode_mapping(mapping data)
{
    mapping out;
    array(mixed) keys;
    int i;
    out = ([]);
    keys = indices(data);
    for(i = 0; i < sizeof(keys); i++) {
        mixed k = keys[i];
        mixed v = data[k];
        mixed rk;
        rk = decode_key(k);
        out[rk] = decode_value(v);
    }
    return out;
}

protected mixed decode_key(mixed k)
{
    int i;
    int digits;
    if(!stringp(k) || sizeof(k) < 2 || k[0] != '#')
        return k;
    i = 1;
    digits = 0;
    if(k[1] == '-') i = 2;
    for(; i < sizeof(k); i++) {
        if(k[i] < '0' || k[i] > '9')
            return k;
        digits++;
    }
    if(!digits) return k;
    return (int)k[1..];
}

protected mixed decode_value(mixed v)
{
    if(mappingp(v)) return decode_mapping(v);
    if(arrayp(v)) {
        array(mixed) out;
        int i;
        out = ({});
        for(i = 0; i < sizeof(v); i++)
            out += ({ decode_value(v[i]) });
        return out;
    }
    return v;
}

//! mapping -> JSON string, ready for SET.
string dumps(mapping data)
{
    return Standards.JSON.encode(encode_mapping(data));
}

//! JSON string -> mapping, with integer keys restored.
mapping loads(string json)
{
    mixed raw;
    raw = Standards.JSON.decode(json);
    if(!mappingp(raw))
        error("Json: top-level JSON value is not an object.\n");
    return decode_mapping(raw);
}
