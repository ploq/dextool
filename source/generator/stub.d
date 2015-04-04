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

alias StubPrefix = Typedef!(string, string.init, "StubPrefix");

version (unittest) {
    shared static this() {
        import std.exception;

        enforce(runUnitTests!(generator.stub)(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

class StubContext {
    /**
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     */
    this(string prefix) {
        this.hdr = new CppModule;
        hdr.suppress_indent(1);
        this.impl = new CppModule;
        impl.suppress_indent(1);

        ctx = ImplStubContext(prefix, hdr, impl);
    }

    void translate(Cursor c) {
        visit_ast!ImplStubContext(c, ctx);
    }

    @property string render_header() {
        return this.hdr.render;
    }

    @property string render_impl() {
        return this.impl.render;
    }

private:
    CppModule hdr;
    CppModule impl;

    ImplStubContext ctx;
}

private:
//TODO use the following typedefs in CppHdrImpl to avoid confusing hdr and impl. Type systems is awesome.
alias CppModuleHdr = Typedef!(CppModule, CppModule.init, "CppHeader");
alias CppModuleImpl = Typedef!(CppModule, CppModule.init, "CppImplementation");
alias CppHdrImpl = Tuple!(CppModule, "hdr", CppModule, "impl");

alias TypeName = Tuple!(string, "type", string, "name");
alias CppClassName = Typedef!(string, string.init, "CppClassName");

/** Traverse the AST and generate a stub by filling the CppModules with data.
 *
 * Params:
 *  prefix = prefix to use for the name of the stub classes.
 *  hdr = C++ code for a header for the stub
 *  impl = C++ code for the implementation of the stub
 */
struct ImplStubContext {
    private string prefix;
    private int indent = 0;
    private CppModule hdr;
    private CppModule impl;

    this(string prefix, CppModule hdr, CppModule impl) {
        this.prefix = prefix;
        this.hdr = hdr;
        hdr.suppress_indent(1);
        this.impl = impl;
        impl.suppress_indent(1);
    }

    void incr() {
        this.indent++;
    }

    void decr() {
        this.indent--;
    }

    bool apply(Cursor c) {
        log_node(c, this.indent);
        bool decend = true;

        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                if (c.isDefinition)
                    (ClassTranslateContext(prefix)).translate(hdr, impl, c);
                decend = false;
                break;

                //case CXCursor_StructDecl
                //case CXCursor_FunctionDecl
                //case CXCursor_TypedefDecl
                //case CXCursor_Namespace
            default:
                break;
            }
        }

        return decend;
    }
}

/** Variables discovered during traversal of AST for a clas.
 *
 */
struct ClassVariabelContainer {
    alias TypeName = Tuple!(string, "type", string, "name");
    private TypeName[] var_decl;

    /** Store new variable in the container.
     * Params:
     *  type = Type of the variable
     *  name = Variable name
     * Example:
     * ---
     * ClassVariabelContainer foo;
     * foo.push("int", "ctor_x");
     * ---
     * The generated declaration is then:
     * ---
     * int ctor_x;
     * ---
     */
    void push(string type, string name) {
        var_decl ~= TypeName(type, name);
    }

    /** Traverse the cursor and store ParmDecl as variables in container.
     *Params:
     *  cursor = AST cursor to a function.
     */
    void push(Cursor c) {
    }

    /** Create declaration of all variables in supplied CppModule.
     *
     * Params:
     *  m = module to create declarations in.
     */
    void injectDeclaration(CppModule m) {
        with (m)
            foreach (type, name; var_decl) {
                stmt(format("%s %s", type, name));
            }
    }
}

/** Translate a ClassDecl to a stub implementation.
 *
 * The generate stub implementation have an interface that the user can control
 * the data flow from stub -> SUT.
 */
struct ClassTranslateContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    /**
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     */
    this(string prefix) {
        this.prefix = prefix;
    }

    void translate(CppModule hdr, CppModule impl, Cursor cursor) {
        this.cursor = cursor;
        this.top = CppHdrImpl(hdr, impl);
        push(top);
        auto c = Cursor(cursor);
        visit_ast!ClassTranslateContext(c, this);
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, depth);
        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                this.name = c.spelling;
                push(classTranslator!CppModule(prefix, name, current));
                break;
            case CXCursor_Constructor:
                ctorTranslator!CppModule(c, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_Destructor:
                dtorTranslator!CppModule(c, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_CXXMethod:
                functionTranslator!CppModule(c, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_CXXAccessSpecifier:
                push(accessSpecifierTranslator!CppModule(c, current.hdr, current.impl));
                break;

            default:
                break;
            }
        }
        return descend;
    }

private:
    Cursor cursor;
    CppHdrImpl top;
    string prefix; // class name prefix
    string name; // class name
    ClassVariabelContainer vars;
}

/** Translate an access specifier to code suitable for a c++ header.
 * Params:
 *  cursor = Cursor to translate
 *  hdr = Header module to append the translation to.
 *  impl = Implementation module to append the translation to (not used).
 */
CppHdrImpl accessSpecifierTranslator(T)(Cursor cursor, ref T hdr, ref T impl) {
    T node;

    with (CXCursorKind) with (CX_CXXAccessSpecifier) final switch (cursor.access.accessSpecifier) {
    case CX_CXXInvalidAccessSpecifier:
        trace(cursor.access.accessSpecifier);
        break;
    case CX_CXXPublic:
        node = hdr.public_;
        break;
    case CX_CXXProtected:
        node = hdr.protected_;
        break;
    case CX_CXXPrivate:
        node = hdr.private_;
        break;
    }

    node.suppress_indent(1);
    return CppHdrImpl(node, impl);
}

CppHdrImpl classTranslator(T)(string prefix, string name, ref CppHdrImpl hdr_impl) {
    T doHeader(string class_prefix, string class_name, ref T hdr) {
        T node;
        with (hdr) {
            node = class_(class_prefix ~ class_name, "public " ~ class_name);
            sep();
        }

        return node;
    }

    return CppHdrImpl(doHeader(prefix, name, hdr_impl.hdr), hdr_impl.impl);
}

void ctorTranslator(T)(Cursor c, ref T hdr, ref T impl) {
    void doHeader(in ref TypeName[] params, ref T hdr) {
        T node;
        if (params.length == 0)
            node = hdr.ctor(c.spelling);
        else
            node = hdr.ctor(c.spelling, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(in ref TypeName[] params, ref T impl) {
    }

    auto params = parmDeclToTypeName(c);
    doHeader(params, hdr);
    doImpl(params, impl);
}

void dtorTranslator(T)(Cursor c, ref T hdr, ref T impl) {
    void doHeader(CppClassName name, ref T hdr) {
        T node = hdr.dtor(cast(string) name);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
        hdr.sep();
    }

    void doImpl(CppClassName name, ref T hdr) {
    }

    CppClassName name = c.spelling;

    doHeader(name, hdr);
    doImpl(name, hdr);
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
TypeName[] parmDeclToTypeName(Cursor cursor) {
    alias toString2 = clang.Token.toString;
    alias toString3 = translator.Type.toString;
    TypeName[] params;

    auto f_group = cursor.tokens;

    foreach (param; cursor.func.parameters) {
        //TODO remove junk
        log_node(param, 0);
        auto tok_group = param.tokens;
        auto type_spelling = toString2(tok_group);
        auto type = translateTypeCursor(param);
        trace(type_spelling, " ", type, " ", param.spelling, "|", param.type.spelling);
        params ~= TypeName(toString3(type), param.spelling);
    }

    trace(params);
    return params;
}

/// Convert a vector of TypeName to string pairs.
auto toStrings(in ref TypeName[] vars) {
    string[] params;

    foreach (tn; vars) {
        params ~= format("%s %s", tn.type, tn.name);
    }

    return params;
}

/// Convert a vector of TypeName to a comma separated string.
auto toString(in ref TypeName[] vars) {
    auto params = vars.toStrings;
    return join(params, ", ");
}

void functionTranslator(T)(Cursor c, ref T hdr, ref T impl) {
    alias toString2 = translator.Type.toString;
    alias toString = generator.stub.toString;

    void doHeader(in ref TypeName[] params, in ref string return_type, ref T hdr) {
        T node;
        if (params.length == 0)
            node = hdr.func(return_type, c.spelling);
        else
            node = hdr.func(return_type, c.spelling, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(in ref TypeName[] params, in ref string return_type, ref T impl) {
    }

    if (!c.func.isVirtual) {
        auto loc = c.location;
        infof("%s:%d:%d:%s: Skipping, not a virtual function", loc.file.name,
            loc.line, loc.column, c.spelling);
        return;
    }

    auto params = parmDeclToTypeName(c);
    auto return_type = toString2(translateTypeCursor(c));
    auto tmp_return_type = toString2(translateType(c.func.resultType));
    trace(return_type, "|", tmp_return_type);

    doHeader(params, return_type, hdr);
    doImpl(params, return_type, impl);
}
