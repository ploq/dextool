/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.conv;
import std.stdio;
import std.experimental.logger;

alias logger = std.experimental.logger;

import docopt;
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
        //assert(runUnitTests!test_stuff(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

@name("Test creating clang types") unittest {
    Index index;
    TranslationUnit translationUnit;
    DiagnosticVisitor diagnostics;
}

@name("Test using clang types") unittest {
    string[] args;
    args ~= "-xc++";

    auto index = Index(false, false);
    auto translationUnit = TranslationUnit.parse(index, "test_files/arrays.h", args);
    scope(exit) translationUnit.dispose;
    scope(exit) index.dispose;

    if (!translationUnit.isValid) {
        writeln("An unknown error occurred");
        //assert(false);
    }

    auto diagnostics = translationUnit.diagnostics;
    if (diagnostics.length > 0) {
        bool translate = true;
        foreach (diag; diagnostics) {
            auto severity = diag.severity;

            with (CXDiagnosticSeverity)
                if (translate)
                    translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);
            writeln(stderr, diag.format);
        }
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

@name("Test creating a Context instance") unittest {
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
        foreach (diag; dia) {
            auto severity = diag.severity;

            with (CXDiagnosticSeverity)
                if (translate)
                    translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);
            writeln(stderr, diag.format);
        }
    }
}

@name("Test diagnostic on a Context, file exist") unittest {
    auto x = new Context("test_files/arrays.h");
    x.diagnostic();
}

@name("Test diagnostic on a Context, no file") unittest {
    auto x = new Context("foobarfailnofile.h");
    x.diagnostic();
}

void visitor1(Context c) {
    foreach (cursor, parent; c.translationUnit.declarations) {
        visitor1(cursor, parent, 0);
    }
}

void visitor1(T1, T2)(T1 cursor, T2 parent, int column) {
    auto indent_str = new char[column * 2];
    foreach (ref c; indent_str)
        c = ' ';

    //writeln(indent_str, "|", to!string(cursor), " # ", to!string(parent));

    writefln("%s|visiting %s [%s line=%d, col=%d]", indent_str, cursor.spelling,
        cursor.kind, cursor.location.spelling.line, cursor.location.spelling.column);

    foreach (c, p; cursor.declarations) {
        visitor1(c, p, column + 1);
    }

    //auto children = cursor.get_children();
    //writeln(to!string(children));
    //with (CXCursorKind)
    //    switch (cursor.kind) {
    //        case CXCursor_StructDecl:
    //            if (cursor.isDefinition)
    //                output.structs ~= code;
    //            break;
    //        case CXCursor_EnumDecl: output.enums ~= code; break;
    //        case CXCursor_UnionDecl: output.unions ~= code; break;
    //        case CXCursor_VarDecl: output.variables ~= code; break;
    //        case CXCursor_FunctionDecl: output.functions ~= code; break;
    //        case CXCursor_TypedefDecl: output.typedefs ~= code; break;
    //
    //        default: continue;
    //    }
}

@name("Test visitor1") unittest {
    auto x = new Context("test_files/typedef_struct.h");
    x.diagnostic();
    x.visitor1();
}

void visitor2(ref Cursor c, ref Cursor p) {
    string indent_str = "";
    writefln("%s|visiting %s [%s line=%d, col=%d]", indent_str, c.spelling, c.kind,
        c.location.spelling.line, c.location.spelling.column);
}

@name("Test Visitor") unittest {
    auto x = new Context("test_files/typedef_struct.h");
    Visitor v = x.translationUnit.cursor;
    foreach (cursor, parent; v) {
        visitor2(cursor, parent);
    }
}

struct VisitorData {
    int column = 0;
    int level = 0;
}

struct MyVisitor {
    alias int delegate(ref Cursor, ref Cursor) Delegate;

    mixin Visitor.Constructors;

    int opApply(Delegate dg) {
        foreach (cursor, parent; visitor) {
            if (auto result = dg(cursor, parent))
                return result;

            if (!cursor.isEmpty) {
                foreach (cursor, parent; Visitor(cursor)) {
                    dg(cursor, parent);
                }
            }
        }

        return 0;
    }
}

@name("Test my visitor") unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    VisitorData data;
    auto visitor3 = delegate void(ref Cursor c, ref Cursor p) { auto indent_str = new char[
        data.column * 2];
    foreach (ref ch; indent_str)
        ch = ' ';

    writefln("%s|visiting %s [%s line=%d, col=%d]", indent_str, c.spelling, c.kind,
        c.location.spelling.line, c.location.spelling.column);
    if (!p.isEmpty)
        data.column += 1;  };

    MyVisitor v = x.translationUnit.cursor;
    foreach (cursor, parent; v) {
        visitor3(cursor, parent);
    }
}

struct MyVisitor2(Env) {
    alias int delegate(ref Cursor, ref Cursor) Delegate;
    // last parameter is the functions environment
    alias void function(ref Cursor cursor, ref Cursor parent, ref Env) ApplyFunc;

    mixin Visitor.Constructors;

    int opApply(Delegate dg) {
        foreach (cursor, parent; visitor) {
            if (auto result = dg(cursor, parent))
                return result;

            if (!cursor.isEmpty) {
                foreach (cursor, parent; Visitor(cursor)) {
                    dg(cursor, parent);
                }
            }
        }

        return 0;
    }
}

@name("Test MyVisitor2 with foreach") unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    auto v = MyVisitor2!VisitorData(x.translationUnit.cursor);
    foreach (c, parent; v) {
        writefln("visiting %s [%s line=%d, col=%d]", c.spelling, c.kind,
            c.location.spelling.line, c.location.spelling.column);
    }
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
        auto indent_str = new char[level * 2];
        foreach (ref ch; indent_str)
            ch = ' ';

        writefln("%s|visiting %s [%s line=%d, col=%d]", indent_str, c.spelling,
            c.kind, c.location.spelling.line, c.location.spelling.column);
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

@name("Test visit_ast with VisitorFoo") unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    VisitorFoo v;
    auto c = x.translationUnit.cursor;
    visit_ast!VisitorFoo(c, v);
}
