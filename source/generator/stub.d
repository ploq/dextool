/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module generator.stub;

import std.algorithm;
import std.ascii;
import std.array;
import std.conv;
import std.range;
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

/// Prefix used for prepending generated code with a unique string to avoid name collisions.
alias StubPrefix = Typedef!(string, string.init, "StubPrefix");
/// Name of a C++ class/struct/namespace.
alias CppClassStructNsName = Typedef!(string, string.init, "CppNestingNs");
/// Nesting of C++ class/struct/namespace.
alias CppNesting = CppClassStructNsName[];

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
    this(StubPrefix prefix) {
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

alias CppClassNesting = Typedef!(string, string.init, "CppNesting");
alias CppClassName = Typedef!(string, string.init, "CppClassName");
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppType = Typedef!(string, string.init, "CppType");
alias CallbackPrefix = Typedef!(string, string.init, "CallbackPrefix");
alias CallbackNs = Typedef!(string, string.init, "CallbackNamespace");
alias DataNs = Typedef!(string, string.init, "DataNamespace");
alias DataStruct = Typedef!(string, string.init, "DataStructInNs");

/** Name mangling that occurs when translating to C++ code.
 */
enum NameMangling {
    Plain, // no mangling
    Method,
    Callback,
    CallCounter,
    ReturnType
}

/** Traverse the AST and generate a stub by filling the CppModules with data.
 *
 * Params:
 *  prefix = prefix to use for the name of the stub classes.
 *  hdr = C++ code for a header for the stub
 *  impl = C++ code for the implementation of the stub
 */
struct ImplStubContext {
    this(StubPrefix prefix, CppModule hdr, CppModule impl) {
        this.prefix = prefix;
        this.hdr = hdr;
        hdr.suppress_indent(1);
        this.impl = impl;
        impl.suppress_indent(1);
        hdr_impl.push(0, CppHdrImpl(hdr, impl));
    }

    void incr() {
        this.level++;
    }

    void decr() {
        nesting.pop(level);
        hdr_impl.pop(level);
        this.level--;
    }

    bool apply(Cursor c) {
        log_node(c, this.level);
        bool decend = true;

        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                if (c.isDefinition) {
                    // interesting part is nesting of ns/class/struct up to
                    // current cursor when used in translator functions.
                    // therefor pushing current ns/class/struct to the stack
                    // for cases it is needed after processing current cursor.
                    (ClassTranslateContext(prefix)).translate(c,
                        nesting.values, hdr_impl.top.hdr, hdr_impl.top.impl);
                    nesting.push(level, CppClassStructNsName(c.spelling));
                }
                break;

                //case CXCursor_StructDecl
                //case CXCursor_FunctionDecl
                //case CXCursor_TypedefDecl
            case CXCursor_Namespace:
                hdr_impl.push(level,
                    namespaceTranslator(CppClassStructNsName(c.spelling), hdr_impl.top.get));
                nesting.push(level, CppClassStructNsName(c.spelling));
                break;
            default:
                break;
            }
        }

        return decend;
    }

private:
    int level = 0;
    StubPrefix prefix;
    CppModule hdr;
    CppModule impl;
    IdStack!(int, CppHdrImpl) hdr_impl;
    IdStack!(int, CppClassStructNsName) nesting;
}

/** Variables discovered during traversal of AST that data storage in the stub.
 * A common case is pointers to callbacks and parameters.
 *
 * NameMangling affects how the types and variables are translated to C++ code.
 * See translate() for details.
 *
 * Example:
 * ---
 * VariableContainer foo;
 * foo.push(NameMangling.Plain, "int", "ctor_x");
 * ---
 * The generated declaration is then:
 * ---
 * int ctor_x;
 * ---
 */
struct VariableContainer {
    private alias InternalType = Tuple!(NameMangling, "mangling", TypeName, "typename");
    private InternalType[] vars;

    void push(in NameMangling mangling, in CppType type, in string name) pure @safe nothrow {
        vars ~= InternalType(mangling, TypeName(cast(TypedefType!CppType) type, name));
    }

    void push(in NameMangling mangling, in ref TypeName tn) {
        vars ~= InternalType(mangling, tn);
    }

    void push(in NameMangling mangling, in ref TypeName[] tn) {
        import std.algorithm.iteration : map;
        import std.range : chain;

        vars = chain(vars, tn.chain().map!(a => InternalType(mangling, a))).array().dup;
    }

    void translate(in CallbackNs cb_ns, in CallbackPrefix cb_prefix,
        in DataNs data_ns, in DataStruct data_st, CppModule hdr, CppModule impl) {
        TypeName InternalToString(in ref InternalType it) pure @safe nothrow {
            TypeName tn;

            final switch (it.mangling) with (NameMangling) {
            case Plain:
                return it.typename;
            case Method:
                return it.typename;
            case Callback:
                tn.type = cb_ns ~ "::" ~ cb_prefix ~ it.typename.type ~ "*";
                tn.name = it.typename.name ~ "_callback";
                return tn;
            case CallCounter:
                tn.type = it.typename.type;
                tn.name = it.typename.name ~ "_cnt";
                return tn;
            case ReturnType:
                tn.type = it.typename.type;
                tn.name = it.typename.name ~ "_return";
                return tn;
            }
        }

        void doHeader() {
            auto ns = hdr.namespace(cast(string) data_ns);
            ns.suppress_indent(1);
            auto st = ns.struct_(cast(string) data_st);
            foreach (item; vars)
                with (st) {
                    TypeName tn = InternalToString(item);
                    stmt(format("%s %s", tn.type, tn.name));
                }
            hdr.sep;
        }

        if (vars.length == 0) {
            return;
        }
        doHeader();
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
    void push(CppType return_type, CppMethodName method, in TypeName[] params) {
        items ~= CallbackType(return_type, method, params.dup);
    }

    /** Generate C++ code in the provided module.
     * Params:
     *  cb_ns = namespace containing generated code for callbacks.
     *  cprefix = prefix for callback interfaces.
     *  data_ns = namespace to generate code in.
     *  hdr = module for generated declaration code.
     *  impl = module for generated implementation code
     */
    void translate(CallbackNs cb_ns, CallbackPrefix cprefix, CppModule hdr, CppModule impl) {
        //TODO ugly with the cast. Cleanup. Maybe functions for converting?
        void doHeader() {
            auto ns = hdr.namespace(cast(string) cb_ns);
            ns.suppress_indent(1);
            foreach (c; items) {
                auto s = ns.struct_(cast(string) cprefix ~ cast(string) c.name);
                s[$.begin = " {", $.noindent = true];
                auto m = s.method(true, cast(string) c.return_type,
                    cast(string) c.name, false, c.params.toString);
                m[$.begin = "", $.end = " = 0; ", $.noindent = true];
                m.set_indentation(1);
            }

            hdr.sep;
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
    this(StubPrefix prefix) {
        this.prefix = prefix;
    }

    void translate(Cursor cursor, const ref CppNesting nesting, CppModule hdr, CppModule impl) {
        import std.array : join;

        void doTraversal() {
            auto c = Cursor(cursor);
            visit_ast!ClassTranslateContext(c, this);
        }

        void doCallbacks(out CallbackNs out_ns, out CallbackPrefix out_cp) {
            CallbackNs cb_ns = prefix ~ "Callback" ~ name;
            CallbackPrefix cp = "I";
            callbacks.translate(cb_ns, cp, hdr, impl);

            out_ns = cb_ns;
            out_cp = cp;
        }

        void doDataStruct(in CallbackNs cb_ns, in CallbackPrefix cb_prefix) {
            DataNs data_ns = prefix ~ "Internal" ~ name;
            DataStruct data_st = prefix ~ "Data";
            vars.translate(cb_ns, cb_prefix, data_ns, data_st, hdr, impl);
        }

        this.cursor = cursor;
        this.top = CppHdrImpl(hdr, impl);
        this.nesting = CppClassNesting(nesting.map!(a => cast(string) a).join("::"));
        push(top);

        doTraversal();

        CallbackNs cb_ns;
        CallbackPrefix cb_prefix;
        doCallbacks(cb_ns, cb_prefix);

        doDataStruct(cb_ns, cb_prefix);
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, depth);
        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                final switch (classdecl_used) {
                case true:
                    descend = false;
                    break;
                case false:
                    this.classdecl_used = true;
                    this.name = cast(CppClassName) c.spelling;
                    push(classTranslator!CppModule(prefix, nesting, name, current.get));
                    break;
                }
                break;
            case CXCursor_Constructor:
                ctorTranslator!CppModule(c, prefix, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_Destructor:
                dtorTranslator!CppModule(c, prefix, vars, callbacks, current.hdr, current.impl);
                descend = false;
                break;
            case CXCursor_CXXMethod:
                functionTranslator!CppModule(c, vars, callbacks, current.hdr, current.impl);
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
    bool classdecl_used;
    Cursor cursor;
    CppHdrImpl top;
    StubPrefix prefix;
    CppClassName name;
    VariableContainer vars;
    CallbackContainer callbacks;
    CppClassNesting nesting;
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

CppHdrImpl classTranslator(T)(StubPrefix prefix, CppClassNesting nesting,
    CppClassName name, ref CppHdrImpl hdr_impl) {
    T doHeader(ref T hdr) {
        T node;
        string stub_class = cast(string) prefix ~ cast(string) name;
        with (hdr) {
            auto n = cast(string) nesting;
            node = class_(stub_class, "public " ~ n ~ (n.length == 0 ? "" : "::") ~ cast(string) name);
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

void dtorTranslator(T)(Cursor c, in StubPrefix prefix, ref VariableContainer vars,
    ref CallbackContainer callbacks, ref T hdr, ref T impl) {
    void doHeader(CppClassName name, CppMethodName callback_name) {
        T node = hdr.dtor(c.func.isVirtual, cast(string) name);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
        hdr.sep();

        callbacks.push(CppType("void"), callback_name, TypeName[].init);
        vars.push(NameMangling.Callback, cast(CppType) callback_name, cast(string) callback_name);
        vars.push(NameMangling.CallCounter, CppType("unsigned"), cast(string) callback_name);
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

void functionTranslator(T)(Cursor c, ref VariableContainer vars,
    ref CallbackContainer callbacks, ref T hdr, ref T impl) {
    //TODO ugly... fix this aliases.
    alias toString2 = translator.Type.toString;
    alias toString = generator.stub.toString;

    string rawTypeToString(in string raw) {
        import std.algorithm.searching : find;

        string r = raw.replace("const", "");
        if (find(r, "&") != string.init) {
            r = r.replace("&", "") ~ "*";
        }

        return r.strip;
    }

    void doHeader(in ref TypeName[] params, in ref string return_type, ref T hdr) {
        import std.algorithm.searching : find;
        import std.algorithm.iteration : map;
        import std.range : chain;

        auto method_name = CppMethodName(c.spelling);
        T node = hdr.method(c.func.isVirtual, return_type,
            cast(string) method_name, c.func.isConst, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];

        //TODO idea. Try and simplify by using enums for operators.
        Nullable!CppMethodName callback_method;
        callback_method = method_name;
        if (find(cast(string) method_name, "operator") != string.init) {
            callback_method = cppOperatorToName(method_name);
            trace(cast(string) callback_method);
            if (callback_method.isNull) {
                errorf("Generating callback function for '%s' not supported",
                    cast(string) method_name);
            }
        }

        callbacks.push(CppType(return_type), callback_method.get, params);
        vars.push(NameMangling.Callback, cast(CppType) callback_method.get,
            cast(string) callback_method.get);
        vars.push(NameMangling.CallCounter, CppType("unsigned"), cast(string) callback_method.get);

        TypeName[] p = params.chain().map!(a => TypeName(rawTypeToString(a.type),
            callback_method.get ~ "_param_" ~ a.name)).array();
        vars.push(NameMangling.Plain, p);

        if (return_type.strip != "void") {
            vars.push(NameMangling.ReturnType,
                CppType(rawTypeToString(return_type)), cast(string) callback_method.get);
        }
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
    ///TODO investigate how tmp_return_type can be used. It is the type with
    //namespace nesting. For example foo::bar::Smurf&.

    doHeader(params, return_type, hdr);
    doImpl(params, return_type, impl);
}

CppHdrImpl namespaceTranslator(CppClassStructNsName nest, ref CppHdrImpl hdr_impl) {
    CppModule doHeader(ref CppModule hdr) {
        auto r = hdr.namespace(cast(string) nest);
        r.suppress_indent(1);
        hdr.sep();
        return r;
    }

    return CppHdrImpl(doHeader(hdr_impl.hdr), hdr_impl.impl);
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
        //TODO remove junk/variables only used in trace(..)
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
