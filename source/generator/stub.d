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

    /** Generate the C++ header file of the stub.
     * Params:
     *  filename = intended output filename, used for ifdef guard.
     */
    string output_header(string filename) {
        auto o = CppHModule(filename);
        o.content.append(this.hdr);

        return o.render;
    }

    string output_impl() {
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
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppType = Typedef!(string, string.init, "CppType");
alias CallbackPrefix = Typedef!(string, string.init, "CallbackPrefix");

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

/// Container of callbacks to generate code for.
struct CallbackContainer {
    /** Add a callback to the container.
     * Params:
     *  type = return type of the method.
     *  method = method name of the callback.
     *  params = parameters the method callback shall accept.
     */
    void push(CppType type, CppMethodName method, in TypeName[] params) {
        items ~= CallbackType(type, method, params.dup);
    }

    /** Generate C++ code in the provided module.
     * The prefix is used in for example namespace containing callbacks.
     * Params:
     *  prefix = prefix for namespace containing generated code.
     *  cprefix = prefix for callback interfaces.
     *  hdr = module for generated declaration code.
     *  impl = module for generated implementation code
     */
    void translate(StubPrefix prefix, CallbackPrefix cprefix, CppModule hdr, CppModule impl) {
        //TODO ugly with the cast. Cleanup. Maybe functions for converting?
        void doHeader() {
            auto ns = hdr.namespace(cast(string) prefix);
            ns.suppress_indent(1);
            foreach (c; items) {
                auto s = ns.struct_(cast(string) cprefix ~ cast(string) c.name);
                s[$.begin = "{", $.noindent = true];
                auto m = s.method(true, cast(string) c.return_type,
                    cast(string) c.name, false, c.params.toString);
                m[$.begin = "", $.end = " = 0; ", $.noindent = true];
                m.set_indentation(1);
            }

            hdr.sep();
        }

        if (items.length == 0) {
            return;
        }
        doHeader();
    }

private:
    alias CallbackType = Tuple!(CppType, "return_type", CppMethodName,
        "name", TypeName[], "params");
    CallbackType[] items;
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
        this.prefix = cast(StubPrefix) prefix;
    }

    void translate(CppModule hdr, CppModule impl, Cursor cursor) {
        void doTraversal() {
            auto c = Cursor(cursor);
            visit_ast!ClassTranslateContext(c, this);
        }

        void doCallbacks() {
            StubPrefix pns = prefix ~ "Callback" ~ name;
            CallbackPrefix cp = "I";
            callbacks.translate(pns, cp, hdr, impl);
        }

        this.cursor = cursor;
        this.top = CppHdrImpl(hdr, impl);
        push(top);

        doTraversal();
        doCallbacks();
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, depth);
        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                this.name = cast(CppClassName) c.spelling;
                push(classTranslator!CppModule(prefix, name, current));
                break;
            case CXCursor_Constructor:
                ctorTranslator!CppModule(c, prefix, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_Destructor:
                dtorTranslator!CppModule(c, prefix, callbacks, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_CXXMethod:
                functionTranslator!CppModule(c, callbacks, current.hdr, current.impl);
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
    StubPrefix prefix;
    CppClassName name;
    ClassVariabelContainer vars;
    CallbackContainer callbacks;
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

CppHdrImpl classTranslator(T)(StubPrefix prefix, CppClassName name, ref CppHdrImpl hdr_impl) {
    T doHeader(ref T hdr) {
        T node;
        string stub_class = cast(string) prefix ~ cast(string) name;
        with (hdr) {
            node = class_(stub_class, "public " ~ cast(string) name);
            sep();
        }

        return node;
    }

    return CppHdrImpl(doHeader(hdr_impl.hdr), hdr_impl.impl);
}

void ctorTranslator(T)(Cursor c, in StubPrefix prefix, ref T hdr, ref T impl) {
    void doHeader(CppClassName name, in ref TypeName[] params) {
        T node;
        node = hdr.ctor(cast(string) name, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(CppClassName name, in ref TypeName[] params) {
    }

    CppClassName name = prefix ~ c.spelling;
    auto params = parmDeclToTypeName(c);
    doHeader(name, params);
    doImpl(name, params);
}

void dtorTranslator(T)(Cursor c, in StubPrefix prefix,
    ref CallbackContainer callbacks, ref T hdr, ref T impl) {
    void doHeader(CppClassName name, CppMethodName callback_name) {
        T node = hdr.dtor(c.func.isVirtual, cast(string) name);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
        hdr.sep();

        callbacks.push(CppType("void"), callback_name, TypeName[].init);
    }

    void doImpl(CppClassName name) {
    }

    CppClassName name = prefix ~ c.spelling.removechars("~");
    CppMethodName callback_name = "dtor" ~ c.spelling.removechars("~");

    doHeader(name, callback_name);
    doImpl(name);
}

auto cppOperatorToName(in ref CppMethodName name) pure nothrow @safe {
    Nullable!CppMethodName r;

    switch (cast(string) name) {
    case "operator=":
        r = CppMethodName("opAssign");
        break;
    default:
        break;
    }

    return r;
}

void functionTranslator(T)(Cursor c, ref CallbackContainer callbacks, ref T hdr, ref T impl) {
    //TODO ugly... fix this aliases.
    alias toString2 = translator.Type.toString;
    alias toString = generator.stub.toString;

    void doHeader(in ref TypeName[] params, in ref string return_type, ref T hdr) {
        import std.algorithm.searching : find;

        auto method_name = CppMethodName(c.spelling);
        T node = hdr.method(c.func.isVirtual, return_type,
            cast(string) method_name, c.func.isConst, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];

        Nullable!CppMethodName callback_method;
        callback_method = method_name;
        if (find(cast(string) method_name, "operator") != string.init) {
            callback_method = cppOperatorToName(method_name);
            if (callback_method.isNull) {
                errorf("Generating callback function for '%s' not supported",
                    cast(string) method_name);
            }
        }

        callbacks.push(CppType(return_type), callback_method.get, params);
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
TypeName[] parmDeclToTypeName(ref Cursor cursor) {
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
auto toStrings(in ref TypeName[] vars) pure @safe nothrow {
    string[] params;

    foreach (tn; vars) {
        params ~= to!string(tn.type) ~ " " ~ to!string(tn.name);
    }

    return params;
}

/// Convert a vector of TypeName to a comma separated string.
auto toString(in ref TypeName[] vars) pure @safe nothrow {
    auto params = vars.toStrings;
    return join(params, ", ");
}
