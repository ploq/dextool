/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.stdio;
import std.conv;
import std.typetuple;
import std.string;
import std.experimental.logger;
alias logger = std.experimental.logger;

import tested;

shared static this() {
    version (unittest) {
        import core.runtime;
        Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!cpp(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

struct KV {
    string k;
    string v;

    this(T)(string k, T v) {
        this.k = k;
        this.v = to!string(v);
    }
}

struct AttrSetter {
    static AttrSetter instance;

    template opDispatch(string name) {
        @property auto opDispatch(T)(T v) {
            static if(name.length > 1 && name[$-1] == '_') {
                return KV(name[0 .. $-1], v);
            }
            else {
                return KV(name, v);
            }
        }
    }
}

interface CppElement {
    abstract string render();
}

class Text: CppElement {
    string contents;
    this(string contents) {
        this.contents = contents;
    }

    override string render() {
        return contents;
    }
}

class Comment: CppElement {
    string contents;
    this(string contents) {
        this.contents = contents;
    }

    override string render() {
        return "// " ~ contents;
    }
}

class CppBase: CppElement {
    string content;
    string[string] attrs;
    CppElement[] children;

    this() {}

    this(string content) {
        this.content = content;
    }

    auto reset() {
        children.length = 0;
        return this;
    }

    override string render() {
        string s = content;
        //foreach(k, v; attrs) {
        //    s ~= k ~ "=\"" ~ v ~ "\" ";
        //}
        //s ~= ">\n";
        foreach(e; children) {
            s ~= e.render();
        }
        return s;
    }

    @property auto _() {
        return this;
    }

    auto opIndex(T...)(T kvs) {
        foreach(kv; kvs) {
            attrs[kv.k] = kv.v;
        }
        return this;
    }

    auto opDollar(int dim)() {
        return AttrSetter.instance;
    }

    auto text(T)(T content) {
        auto e = new Text(to!string(content));
        children ~= e;
        return this;
    }
    alias opCall = text;

    auto comment(string comment) {
        auto e = new Comment(comment);
        children ~= e;
        return this;
    }

    auto suite(T...)(auto ref T args) {
        auto e = new CppSuite(args);
        children ~=e;
        return e;
    }

    //auto _append(string content) {
    //    auto e = new CppBase(content);
    //    children ~= e;
    //    return e;
    //}
    //
    //auto _append(string content, string content) {
    //    auto e = new CppBase(content);
    //    e.text(content);
    //    children ~= e;
    //    return e;
    //}

    //protected static string _makeSubelems(E...)() {
    //    string s = "";
    //    foreach(name; E) {
    //        s ~= "auto " ~ name ~ "(T...)(auto ref T args) {\n";
    //        static if (name[$-1] == '_') {
    //            s ~= "    return _append(\"" ~ name[0 .. $-1] ~ "\", args);";
    //        }
    //        else {
    //            s ~= "    return _append(\"" ~ name ~ "\", args);";
    //        }
    //        s ~= "}\n";
    //    }
    //    return s;
    //}

    //mixin(_makeSubelems!("head", "title", "meta", "style", "link", "script",
    //        "body_", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6", "p", "table", "tr", "td",
    //        "a", "li", "ul", "ol", "img", "br", "em", "strong", "input", "pre", "label", "iframe", ));
}

class CppSuite : CppBase {
    this(T...)(string headline, auto ref T args) {
        if (args.length > 0) {
            headline = format(headline, args);
        }
        super(headline);
    }

    override string render() {
        string s = super.content;
        string begin = " {";
        string end = "}";

        if ("begin" in attrs) {
            begin = attrs["begin"];
        }
        if ("end" in attrs) {
            end = attrs["end"];
        }

        s ~= begin;
        foreach(e; children) {
            s ~= e.render();
        }
        s ~= end;

        return s;
    }
}

@name("Test of empty CppSuite")
unittest {
    auto x = new CppSuite("test");
    writeln(x.render());
    assert(x.render() == "test {}");
}

@name("Test of CppSuite with formatting")
unittest {
    auto x = new CppSuite("if (%s)", "x > 5");
    writeln(x.render());
    assert(x.render() == "if (x > 5) {}");
}

@name("Test of CppSuite with simple text")
unittest {
    auto x = new CppSuite("foo");
    with (x) {
        text("bar");
    }
    writeln(x.render());
    assert(x.render() == "foo {bar}");
}

@name("Test of CppSuite with simple text and changed begin")
unittest {
    auto x = new CppSuite("foo");
    with (x[$.begin = "_:_"]) {
        text("bar");
    }
    writeln(x.render());
    assert(x.render() == "foo_:_bar}");
}

@name("Test of CppSuite with simple text and changed end")
unittest {
    auto x = new CppSuite("foo");
    with (x[$.end = "_:_"]) {
        text("bar");
    }
    writeln(x.render());
    assert(x.render() == "foo {bar_:_");
}

@name("Test of nested CppSuite")
unittest {
    auto x = new CppSuite("foo");
    with (x) {
        text("bar ");
        with (suite("smurf")) {
            text("bar");
        }
    }
    writeln(x.render());
    assert(x.render() == "foo {bar smurf {bar}}");
}

class CppHdr : CppBase {
    this() {
        super();
    }

    override string render() {
        return super.render();
    }
}

@name("Test of text in CppBase")
unittest {
    CppHdr cpp_hdr = new CppHdr;

    with (cpp_hdr) {
        text("foo");
        comment("some stuff");
    }

    writeln(cpp_hdr.render);
}
