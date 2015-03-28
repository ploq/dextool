/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module generator.stub;

import std.ascii;
import std.array;
import std.conv;
import std.stdio;
import std.string;
import std.typecons;
import std.experimental.logger;

import tested;

import clang.c.index;
import clang.Cursor;
import clang.Index;
import clang.Token;
import clang.TranslationUnit;
import clang.Visitor;
import clang.UnsavedFile;

import dsrcgen.cpp;

import translator.Type;

import generator.analyzer;

version (unittest) {
    shared static this() {
        import std.exception;

        enforce(runUnitTests!(generator.stub)(new ConsoleTestResultWriter), "Unit tests failed.");
    }
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
        log_node(c, this.indent);
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
            default:
                break;
            }
        }

        return decend;
    }

    @property string render() {
        return this.output_;
    }
}

struct ClassTranslatorHdr {
    mixin VisitNodeModule!CppModule;

    private Cursor cursor;
    private CppModule top;

    this(Cursor cursor) {
        this.cursor = cursor;
        top = new CppModule;
        top.suppress_indent(1);
        push(top);
    }

    string translate() {
        auto c = Cursor(this.cursor);
        visit_ast!ClassTranslatorHdr(c, this);

        return top.render;
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, level);
        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                with (current) {
                    push(class_(c.spelling));
                    sep();
                }
                break;
            case CXCursor_Constructor:
                CtorTranslator!CppModule(c, current)[$.begin = "",
                    $.end = ";" ~ newline, $.noindent = true];
                descend = false;
                break;
            case CXCursor_Destructor:
                DtorTranslator!CppModule(c, current)[$.begin = "",
                    $.end = ";" ~ newline, $.noindent = true];
                descend = false;
                current.sep();
                break;
            case CXCursor_CXXMethod:
                FunctionTranslator!CppModule(c, current)[$.begin = "",
                    $.end = ";" ~ newline, $.noindent = true];
                descend = false;
                break;
            case CXCursor_CXXAccessSpecifier:
                push(AccessSpecifierTranslator!CppModule(c, current));
                break;

            default:
                break;
            }
        }
        return descend;
    }
}

/** Translate an access specifier to code suitable for a c++ header.
 * Params:
 *  cursor = Cursor to translate
 *  top = Top module to append the translation to.
 */
T AccessSpecifierTranslator(T)(Cursor cursor, ref T top) {
    T node;

    with (CXCursorKind) with (CX_CXXAccessSpecifier) final switch (cursor.access.accessSpecifier) {
    case CX_CXXInvalidAccessSpecifier:
        trace(cursor.access.accessSpecifier);
        break;
    case CX_CXXPublic:
        node = top.public_;
        break;
    case CX_CXXProtected:
        node = top.protected_;
        break;
    case CX_CXXPrivate:
        node = top.private_;
        break;
    }

    node.suppress_indent(1);
    return node;
}

T CtorTranslator(T)(Cursor c, ref T top) {
    T node;

    auto params = ParmDeclToString(c);
    if (params.length == 0)
        node = top.ctor(c.spelling);
    else
        node = top.ctor(c.spelling, join(params, ", "));

    return node;
}

T DtorTranslator(T)(Cursor c, ref T top) {
    T node = top.dtor(c.spelling);
    return node;
}

/** Travers a node tree and gather all paramdecl converting them to a string.
 * Params:
 * cursor = A node containing ParmDecl nodes as children.
 * Example:
 * -----
 * class Simple{ Simple(char x, char y); }
 * -----
 * The AST for the above is kind of the following:
 * Example:
 * ---
 * Simple [CXCursor_Constructor Type(CXType(CXType_FunctionProto))
 *   x [CXCursor_ParmDecl Type(CXType(CXType_Char_S))
 *   y [CXCursor_ParmDecl Type(CXType(CXType_Char_S))
 * ---
 * It is translated to the string "char x, char y".
 */
string[] ParmDeclToString(Cursor cursor) {
    string[] params;

    auto f_group = cursor.tokens;

    foreach (param; cursor.func.parameters) {
        log_node(param, 0);
        auto tok_group = param.tokens;
        auto type_spelling = tok_group.toString;
        auto type = translateTypeCursor(param);
        trace(type_spelling, " ", type, " ", param.spelling, "|", param.type.spelling);
        params ~= format("%s %s", type.toString, param.spelling);
    }

    trace(params);
    return params;
}

T FunctionTranslator(T)(Cursor c, ref T top) {
    T node;

    string[] params = ParmDeclToString(c);
    auto return_type = translateTypeCursor(c).toString;
    auto tmp_return_type = translateType(c.func.resultType).toString;
    trace(return_type, "|", tmp_return_type);
    if (params.length == 0)
        node = top.func(return_type, c.spelling);
    else
        node = top.func(return_type, c.spelling, join(params, ", "));

    return node;
}
