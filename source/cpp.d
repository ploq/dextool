/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.algorithm;
import std.ascii;
import std.conv;
import std.stdio;
import std.string;
import std.typetuple;

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

interface BaseElement {
    abstract string render();
    abstract string _render_indent(int level);
    abstract string _render_recursive(int level);
    abstract string _render_post_recursive(int level);
}

class BaseModule : BaseElement {
    static int indent_width = 4;

    BaseElement[] children;
    int sep_lines;
    int suppress_indent_;

    this() {}

    this(int indent_width) {
        this.indent_width = indent_width;
    }

    /// Number of levels to suppress indent
    void suppress_indent(int levels) {
        this.suppress_indent_ = levels;
    }

    auto reset() {
        children.length = 0;
        return this;
    }

    /// Separate with at most count empty lines.
    void sep(int count = 1) {
        count -= sep_lines;
        if (count <= 0)
            return;
        foreach(i; 0 .. count) {
            children ~= new Text(newline);
        }

        sep_lines += count;
    }

    string indent(string s, int level) {
        level = max(0, level);
        char[] indent;
        indent.length = indent_width*level;
        indent[] = ' ';

        return to!string(indent) ~ s;
    }

    void _append(BaseElement e) {
        children ~= e;
        sep_lines = 0;
    }

    override string _render_indent(int level) {
        return "";
    }

    override string _render_recursive(int level) {
        level -= suppress_indent_;
        string s = _render_indent(level);

        foreach(e; children) {
            s ~= e._render_recursive(level+1);
        }
        s ~= _render_post_recursive(level);

        return s;
    }

    override string _render_post_recursive(int level) {
        return "";
    }

    override string render() {
        string s = _render_indent(0);
        foreach(e; children) {
            s ~= e._render_recursive(0 - suppress_indent_);
        }
        s ~= _render_post_recursive(0);

        return _render_recursive(0);
    }
}

class Text: BaseModule {
    string contents;
    this(string contents) {
        this.contents = contents;
    }

    override string _render_indent(int level) {
        return contents;
    }
}

class Comment: BaseModule {
    string contents;
    this(string contents) {
        this.contents = contents;
        sep();
    }

    override string _render_indent(int level) {
        return indent("// " ~ contents, level);
    }
}

class CppModule: BaseModule {
    string[string] attrs;

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
        _append(e);
        return this;
    }
    alias opCall = text;

    auto comment(string comment) {
        auto e = new Comment(comment);
        _append(e);
        return this;
    }

    auto base() {
        auto e = new CppModule;
        super._append(e);
        return e;
    }

    // Statements
    auto stmt(string stmt_) {
        auto e = new CppStmt(stmt_);
        _append(e);
        return e;
    }

    auto break_() {
        auto e = stmt("break");
        return e;
    }

    auto continue_() {
        auto e = stmt("continue");
        return e;
    }

    auto return_(string expr) {
        auto e = stmt(format("return %s", expr));
        return e;
    }

    auto goto_(string name) {
        auto e = stmt(format("goto %s", name));
        return e;
    }

    auto label(string name) {
        auto e = stmt(format("%s:", name));
        return e;
    }

    auto define(string name) {
        auto e = stmt(format("#define %s", name));
        e[$.end = ""];
        return e;
    }

    auto define(string name, string value) {
        // may need to replace \n with \\\n
        auto e = stmt(format("#define %s %s", name, value));
        e[$.end = ""];
        return e;
    }

    // Suites
    auto suite(string headline) {
        auto e = new CppSuite(headline);
        _append(e);
        sep();
        return e;
    }

    auto IFNDEF(string name) {
        auto e = suite(format("#ifndef %s", name));
        e[$.begin = newline, $.end = format("#endif // %s", name)];
        return e;
    }

    //auto _append(string content) {
    //    auto e = new CppModule(content);
    //    children ~= e;
    //    return e;
    //}

    //auto _append(string content, string content) {
    //    auto e = new CppModule(content);
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

string stmt_append_end(string s, in ref string[string] attrs) pure nothrow @safe {
    bool in_pattern = false;
    try {
        in_pattern = inPattern(s[$-1], ";:,{");
    } catch (Exception e) {}

    if (!in_pattern && s[0] != '#') {
        string end = ";";
        if ("end" in attrs) {
            end = attrs["end"];
        }
        s ~= end;
    }

    return s;
}

@name("Test of stmt_append_end")
unittest {
    string[string] attrs;
    string stmt = "some_line";
    string result = stmt_append_end(stmt, attrs);
    assert(stmt ~ ";" == result, result);

    result = stmt_append_end(stmt ~ ";", attrs);
    assert(stmt ~ ";" == result, result);

    attrs["end"] = "{";
    result = stmt_append_end(stmt, attrs);
    assert(stmt ~ "{" == result, result);
}

class CppStmt : CppModule {
    string stmt;

    this(string stmt) {
        this.stmt = stmt;
        sep();
    }

    override string _render_indent(int level) {
        return stmt_append_end(stmt, attrs);
    }
}

class CppSuite : CppModule {
    string headline;

    this(string headline) {
        this.headline = headline;
    }

    override string _render_indent(int level) {
        string r = headline ~ " {" ~ newline;
        if ("begin" in attrs) {
            r = headline ~ attrs["begin"];
        }
        return indent(r, level);
    }

    override string _render_post_recursive(int level) {
        string r = "}";
        if ("end" in attrs) {
            r = attrs["end"];
        }
        return indent(r, level);
    }
}

@name("Test of empty CppSuite")
unittest {
    auto x = new CppSuite("test");
    assert(x.render == "test {\n}", x.render);
}

@name("Test of CppSuite with formatting")
unittest {
    auto x = new CppSuite("if (x > 5)");
    assert(x.render() == "if (x > 5) {\n}", x.render);
}

@name("Test of CppSuite with simple text")
unittest {
    // also test that text(..) do NOT add a linebreak
    auto x = new CppSuite("foo");
    with (x) {
        text("bar");
    }
    assert(x.render() == "foo {\nbar}", x.render);
}

@name("Test of CppSuite with simple text and changed begin")
unittest {
    auto x = new CppSuite("foo");
    with (x[$.begin = "_:_"]) {
        text("bar");
    }
    assert(x.render() == "foo_:_bar}", x.render);
}

@name("Test of CppSuite with simple text and changed end")
unittest {
    auto x = new CppSuite("foo");
    with (x[$.end = "_:_"]) {
        text("bar");
    }
    assert(x.render() == "foo {\nbar_:_", x.render);
}

@name("Test of nested CppSuite")
unittest {
    auto x = new CppSuite("foo");
    with (x) {
        text("bar");
        sep();
        with (suite("smurf")) {
            comment("bar");
        }
    }
    assert(x.render() == """foo {
bar
    smurf {
        // bar
    }
}""", x.render);
}

/// Code generation for C++ header.
struct CppHdr {
    string ifdef_guard;
    CppModule doc;
    CppModule header;
    CppModule content;
    CppModule footer;

    this(string ifdef_guard) {
        // Must suppress indentation to generate what is expected by the user.
        this.ifdef_guard = ifdef_guard;
        doc = new CppModule;
        with (doc) {
            suppress_indent(1);
            header = base;
            header.suppress_indent(1);
            with (IFNDEF(ifdef_guard)) {
                suppress_indent(1);
                define(ifdef_guard);
                content = base;
                content.suppress_indent(1);
            }
            footer = base;
            footer.suppress_indent(1);
        }
    }

    auto render() {
        return doc.render();
    }
}

@name("Test of text in CppModule with guard")
unittest {
    auto hdr = CppHdr("somefile_hpp");

    with (hdr.header) {
        text("header text");
        sep();
        comment("header comment");
    }
    with (hdr.content) {
        text("content text");
        sep();
        comment("content comment");
    }
    with (hdr.footer) {
        text("footer text");
        sep();
        comment("footer comment");
    }

    assert(hdr.render == """header text
// header comment
#ifndef somefile_hpp
#define somefile_hpp
content text
// content comment
#endif // somefile_hpp
footer text
// footer comment
""", hdr.render);
}
