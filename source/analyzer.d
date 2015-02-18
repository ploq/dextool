/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.container;
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
import clang.UnsavedFile;

import cpp;

version (unittest) {
    shared static this() {
        import std.exception;
        enforce(runUnitTests!analyzer(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

// Holds the context of the file.
class Context {
    /// Initialize context from file
    this(string input_file) {
        this.input_file = input_file;
        this.index = Index(false, false);
        this.translation_unit = TranslationUnit.parse(this.index, this.input_file, this.args);
    }

    ~this() {
        translation_unit.dispose;
        index.dispose;
    }

private:
    static string[] args = ["-xc++"];
    string input_file;
    Index index;
    TranslationUnit translation_unit;
}

@name("Test creating a Context instance")
unittest {
    auto x = new Context("test_files/arrays.h");
}

// No errors occured during translation.
bool isValid(Context context) {
    return context.translation_unit.isValid;
}

// Print diagnostic error messages.
void diagnostic(Context context) {
    if (!context.isValid())
        return;

    auto dia = context.translation_unit.diagnostics;
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

// If apply returns true visit_ast will decend into the node if it contains children.
void visit_ast(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    bool decend = v.apply(cursor);

    if (!cursor.isEmpty && decend) {
        v.incr();
        foreach (c, p; Visitor(cursor)) {
            visit_ast(c, v);
        }
        v.decr();
    }
}

void log_node(T)(in ref T parent, ref Cursor c, int level,) {
    auto indent_str = new char[level*2];
    foreach (ref ch ; indent_str) ch = ' ';

    logf("%s|visiting %s [%s line=%d, col=%d, def=%d] %s",
         indent_str,
         c.spelling,
         c.kind,
         c.location.spelling.line,
         c.location.spelling.column,
         c.isDefinition,
         typeid(parent));
}

@name("Test visit_ast with VisitorFoo")
unittest {
    struct VisitorFoo {
        public int count;
        private int indent;

        void incr() {
            this.indent += 1;
        }

        void decr() {
            this.indent -= 1;
        }

        bool apply(ref Cursor c) {
            log_node(this, c, this.indent);
            count++;
            return true;
        }
    }

    auto x = new Context("test_files/class.h");
    x.diagnostic();

    VisitorFoo v;
    auto c = x.translation_unit.cursor;
    visit_ast!VisitorFoo(c, v);
    assert(v.count == 40);
}

struct TranslateContext {
    private int indent = 0;
    private string output_;

    void incr() {
        this.indent += 1;
    }

    void decr() {
        this.indent -= 1;
    }

    bool apply(Cursor c) {
        log_node(this, c, this.indent);
        bool decend = true;

        with (CXCursorKind) {
            switch (c.kind) {
                case CXCursor_ClassDecl:
                    if (c.isDefinition)
                        output_ ~= (ClassTranslatorHdr(c)).translate;
                    decend = false;
                    break;

                //case CXCursor_StructDecl:
                //    if (cursor.isDefinition)
                //        output.structs ~= code;
                //    break;
                //case CXCursor_EnumDecl: output.enums ~= code; break;
                //case CXCursor_UnionDecl: output.unions ~= code; break;
                //case CXCursor_VarDecl: output.variables ~= code; break;
                //case CXCursor_FunctionDecl: output.functions ~= code; break;
                //case CXCursor_TypedefDecl: output.typedefs ~= code; break;
                default: break;
            }
        }

        return decend;
    }

    @property string output() {
        return this.output_;
    }
}

@name("Test of TranslateContext")
unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output.length > 0);
}

struct ClassTranslatorHdr {
    private CXCursor cursor;

    CppModule code; // top code generator node
    CppModule[] stack; // stack of cpp nodes
    int level;

    void incr() {
        level++;
    }
    void decr() {
        level--;
        if (stack.length > 0)
            logger.log(cast(void*)(stack[$-1]), " ", to!string(stack[$-1]));
        if (stack.length > 1)
            stack.length = stack.length - 1;
    }

    this(CXCursor cursor) {
        this.cursor = cursor;
        code = new CppModule;
        push(code);
    }

    this(Cursor cursor) {
        this.cursor = cursor.cx;
        code = new CppModule;
        push(code);
    }

    string translate() {
        auto c = Cursor(this.cursor);
        visit_ast!ClassTranslatorHdr(c, this);

        return code.render;
    }

    bool apply(Cursor c) {
        log_node(this, c, level);
        with (CXCursorKind)
            switch (c.kind) {
                case CXCursor_ClassDecl:
                    with(current) {
                        push(class_(c.spelling));
                        sep();
                    }
                    break;
                case CXCursor_CXXAccessSpecifier:
                    with(current) {
                        push(public_);
                    }
                    break;

                default: break;
            }
        return true;
    }

    ref CppModule current() {
        if (stack.length > 0)
            logger.log(cast(void*)(stack[$-1]), " ", to!string(stack[$-1]));
        return stack[$-1];
    }

    void push(T)(T c) {
        stack ~= cast(CppModule)(c);
        if (stack.length > 0)
            logger.log(cast(void*)(stack[$-1]), " ", to!string(c));
    }
}

@name("Test of ClassTranslatorHdr")
unittest {
    auto x = new Context("test_files/class.h");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}
