/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.conv;
import std.stdio;
import std.experimental.logger;
alias logger = std.experimental.logger;

import tested;

import clang.c.index;
import clang.Index;
import clang.TranslationUnit;
import clang.Visitor;
import clang.Cursor;

shared static this() {
    version (unittest) {
        import core.runtime;
        Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!analyzer(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

// Holds the context of the file.
class Context {
    this(string inputFile) {
        this.inputFile = inputFile;
        this.index = Index(false, false);
        this.translationUnit = TranslationUnit.parse(this.index, this.inputFile, this.args);
    }

    ~this() {
        translationUnit.dispose;
        index.dispose;
    }

private:
    static string[] args = ["-xc++"];
    string inputFile;
    Index index;
    TranslationUnit translationUnit;
}

@name("Test creating a Context instance")
unittest {
    auto x = new Context("test_files/arrays.h");
}

bool isValid(Context context) {
    return context.translationUnit.isValid;
}

void diagnostic(Context context) {
    if (!context.isValid())
        return;

    auto dia = context.translationUnit.diagnostics;
    if (dia.length > 0) {
        bool translate = true;
        foreach (diag ; dia)
        {
            auto severity = diag.severity;

            with (CXDiagnosticSeverity)
                if (translate)
                    translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);
            writeln(stderr, diag.format);
        }
    }
}

@name("Test diagnostic on a Context, file exist")
unittest {
    auto x = new Context("test_files/arrays.h");
    x.diagnostic();
}

@name("Test diagnostic on a Context, no file")
unittest {
    auto x = new Context("foobarfailnofile.h");
    x.diagnostic();
}

struct VisitorFoo {
    private int level = 0;

    void incr() {
        this.level += 1;
    }

    void decr() {
        this.level -= 1;
    }

    void apply(ref Cursor c) {
        auto indent_str = new char[level*2];
        foreach (ref ch ; indent_str) ch = ' ';

        writefln("%s|visiting %s [%s line=%d, col=%d]",
                 indent_str,
                 c.spelling,
                 c.kind,
                 c.location.spelling.line,
                 c.location.spelling.column);
    }
}

void visit_ast(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    v.apply(cursor);

    if (!cursor.isEmpty) {
        v.incr();
        foreach (c, p; Visitor(cursor)) {
            visit_ast(c, v);
        }
        v.decr();
    }
}

@name("Test visit_ast with VisitorFoo")
unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    VisitorFoo v;
    auto c = x.translationUnit.cursor;
    visit_ast!VisitorFoo(c, v);
}
