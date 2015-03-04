/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
import std.container;
import std.conv;
import std.stdio;
import std.typecons;
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
    v.incr();
    bool decend = v.apply(cursor);

    if (!cursor.isEmpty && decend) {
        foreach (c, p; Visitor(cursor)) {
            visit_ast(c, v);
        }
    }
    v.decr();
}

void log_node(T)(in ref T parent, ref Cursor c, int level,) {
    auto indent_str = new char[level*2];
    foreach (ref ch ; indent_str) ch = ' ';

    logf("%s|%s [%s %s line=%d, col=%d, def=%d] %s",
         indent_str,
         c.spelling,
         c.kind,
         c.type,
         c.location.spelling.line,
         c.location.spelling.column,
         c.isDefinition,
         typeid(parent));
}

/// T is module type.
mixin template VisitNodeModule(Tmodule) {
    alias Entry = Tuple!(Tmodule, "node", int, "level");
    Entry[] stack; // stack of cpp nodes
    int level;

    void incr() {
        level++;
        //logger.log(level, " ", stack.length);
    }

    void decr() {
        // remove node leaving the level
        if (stack.length > 1 && stack[$-1].level == level) {
            //logger.log(cast(void*)(stack[$-1].node), " ", to!string(stack[$-1]), level);
            stack.length = stack.length - 1;
        }
        level--;
    }

    ref Tmodule current() {
        //if (stack.length > 0)
        //    logger.log(cast(void*)(stack[$-1].node), " ", to!string(stack[$-1]));
        return stack[$-1].node;
    }

    T push(T)(T c) {
        stack ~= Entry(cast(Tmodule)(c), level);
        //if (stack.length > 0)
        //    logger.log(cast(void*)(stack[$-1].node), " ", to!string(stack[$-1]));
        return c;
    }
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
    mixin VisitNodeModule!CppModule;

    private CXCursor cursor;
    private CppModule top; // top code generator node

    this(CXCursor cursor) {
        this.cursor = cursor;
        top = new CppModule;
        push(top);
    }

    this(Cursor cursor) {
        this.cursor = cursor.cx;
        top = new CppModule;
        push(top);
    }

    string translate() {
        auto c = Cursor(this.cursor);
        visit_ast!ClassTranslatorHdr(c, this);

        return top.render;
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(this, c, level);
        with (CXCursorKind) {
            switch (c.kind) {
                case CXCursor_ClassDecl:
                    with(current) {
                        push(class_(c.spelling));
                        sep();
                    }
                    break;
                case CXCursor_Constructor:
                    CtorTranslator(c, current).translate;
                    descend = false;
                    break;
                case CXCursor_CXXMethod:
                    break;
                case CXCursor_CXXAccessSpecifier:
                    AccessSpecifierTranslator!CppModule(c, current, &push!CppModule);
                    break;

                default: break;
            }
        }
        return descend;
    }
}

/// Translate an access specifier to code suitable for a c++ header.
/// @param cursor Cursor to translate
/// @param top Top module to append the translation to.
/// @param push Function used to push the created node to the indent queue.
void AccessSpecifierTranslator(T)(Cursor cursor, ref T top, T delegate(T c) push) {
    T current;

    with (CXCursorKind) {
        final switch (cursor.access.accessSpecifier) {
            with(CX_CXXAccessSpecifier) {
                case CX_CXXInvalidAccessSpecifier:
                    logger.log(cursor.access.accessSpecifier); break;
                case CX_CXXPublic:
                    current = push(top.public_);
                    break;
                case CX_CXXProtected:
                    current = push(top.protected_);
                    break;
                case CX_CXXPrivate:
                    current = push(top.private_);
                    break;
            }
        }
    }

    current.suppress_indent(1);
}

struct CtorTranslator {
    mixin VisitNodeModule!CppModule;

    private CXCursor cursor;
    private CppModule top; // top code generator node

    this(CXCursor cursor, ref CppModule top) {
        this.cursor = cursor;
        this.top = top;
        push(top);
    }

    this(Cursor cursor, ref CppModule top) {
        this.cursor = cursor.cx;
        this.top = top;
        push(top);
    }

    void translate() {
        auto c = Cursor(this.cursor);
        visit_ast!CtorTranslator(c, this);
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(this, c, level);
        switch(c.kind) {
            case CXCursorKind.CXCursor_Constructor:
                push(current.ctor(c.spelling));
                break;
            case CXCursorKind.CXCursor_ParmDecl:
                break;
            default: break;
        }

        return descend;
    }
}

@name("Test of ClassTranslatorHdr, class_simple.hpp")
unittest {
    auto x = new Context("test_files/class_simple.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}

@name("Test of ClassTranslatorHdr, class_nested.hpp")
unittest {
    auto x = new Context("test_files/class_nested.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}

@name("Test of ClassTranslatorHdr, class_impl.hpp")
unittest {
    auto x = new Context("test_files/class_impl.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}

@name("Test of ClassTranslatorHdr, class_simple2.hpp")
unittest {
    auto x = new Context("test_files/class_simple2.hpp");
    x.diagnostic();

    TranslateContext ctx;
    auto cursor = x.translation_unit.cursor;
    visit_ast!TranslateContext(cursor, ctx);
    //assert(ctx.output == "");
    writeln(ctx.output);
}
