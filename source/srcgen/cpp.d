/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module cpp;
import std.algorithm;
import std.ascii;
import std.conv;
import std.string;

import tested;

import base;
import c;

shared static this() {
    version (unittest) {
        import core.runtime;
        Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!cpp(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

class CppModule: CModule {
    // Suites
    auto namespace(T)(T name) {
        string n = to!string(name);
        auto e = suite(format("namespace %s", n));
        e[$.end = format("} //NS:%s%s", n, newline)];
        return e;
    }

    auto class_(T)(T name) {
        string n = to!string(name);
        auto e = suite(format("class %s", n));
        e[$.end = format("};%s", newline)];
        return e;
    }

    auto class_(T0, T1)(T0 name, T1 inherit) {
        string n = to!string(name);
        string ih = to!string(inherit);
        if (ih.length == 0) {
            return class_(name);
        } else {
            auto e = suite(format("class %s : %s", n, ih));
            e[$.end = format("};%s", newline)];
            return e;
        }
    }

    auto public_() {
        auto e = suite("public:");
        e[$.begin = newline, $.end = ""];
        return e;
    }

    auto protected_() {
        auto e = suite("protected:");
        e[$.begin = newline, $.end = ""];
        return e;
    }

    auto private_() {
        auto e = suite("private:");
        e[$.begin = newline, $.end = ""];
        return e;
    }
}

@name("Test of C++ suits")
unittest {
    string expect = """
    namespace foo {
    } //NS:foo
    class Foo {
    };
    class Foo : Bar {
    };
    public:
        return 5;
    protected:
        return 7;
    private:
        return 8;
""";
    auto x = new CppModule();
    with(x) {
        sep;
        namespace("foo");
        class_("Foo");
        class_("Foo", "Bar");
        with(public_) {
            return_(5);
        }
        with(protected_) {
            return_(7);
        }
        with(private_) {
            return_(8);
        }
    }

    auto rval = x.render();
    assert(rval == expect, rval);
}
