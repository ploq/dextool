/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Utility useful for plugins.
*/
module plugin.utility;

import logger = std.experimental.logger;

import plugin.types : CliBasicOption, CliOptionParts;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

/** Make a static c'tor that creates an instance with all class members initialized.
 *
 * Params:
 *   T = type to construct an instance of
 *   postInit = call the function with the initialized instance.
 */
mixin template MakerInitializingClassMembers(T, alias postInit = function void(ref T) {
}) {
    static T make() {
        T inst;

        foreach (member; __traits(allMembers, T)) {
            alias MemberT = typeof(__traits(getMember, inst, member));
            static if (is(MemberT == class)) {
                __traits(getMember, inst, member) = new MemberT;
            }
        }

        postInit(inst);

        return inst;
    }
}

/** Convenient array with support for marking of elements for later removal.
 */
struct MarkArray(T) {
    import std.array : Appender;

    alias Range = T[];
    private Appender!(size_t[]) remove_;
    private Appender!(T*[]) arr;

    /// Store e in the cache.
    void put(T e) {
        auto item = new T;
        *item = e;
        arr.put(item);
    }

    /// Retrieve a slice of the stored data.
    auto data() {
        import std.algorithm : map;

        return arr.data.map!(a => *a);
    }

    /** Mark index `idx` for removal.
     *
     * Later as in calling $(D doRemoval).
     */
    void markForRemoval(size_t idx) @safe pure {
        remove_.put(idx);
    }

    /// Remove all items that has been marked.
    void doRemoval() {
        import std.algorithm : canFind, filter, map;
        import std.range : enumerate;

        // naive implementation. Should use swapping instead.
        typeof(arr) new_;
        new_.put(arr.data.enumerate.filter!(a => !canFind(remove_.data,
                a.index)).map!(a => a.value));
        arr.clear;
        remove_.clear;

        arr = new_;
    }

    /// Clear the $(D MarkArray).
    void clear() {
        arr.clear;
        remove_.clear;
    }
}

@Name("Should store item")
unittest {
    MarkArray!int arr;

    arr.put(10);

    arr.data.length.shouldEqual(1);
    arr.data[0].shouldEqual(10);
}

@Name("Should mark and remove items")
unittest {
    MarkArray!int arr;
    arr ~= [10, 20, 30];

    arr.markForRemoval(1);
    arr[].length.shouldEqual(3);

    arr.doRemoval;

    arr[].length.shouldEqual(2);
    arr[0].shouldEqual(10);
    arr[1].shouldEqual(30);
}

/** Merge basic options with the plugin specific to a docopt compatible string.
 *
 * Params:
 *  basic_options = options that are reused between plugins
 *  opt = specific options for the plugin
 */
auto toDocopt(CliBasicOption basic, CliOptionParts opt) {
    import std.format : format;
    import plugin.types : CliDocoptOption;

    auto r = format("%s

options:%s%s

%s", opt.usage, basic, opt.optional, opt.others);

    debug logger.trace("raw: { Begin CLI\n", r, "\n} End CLI");
    return CliDocoptOption(r);
}
