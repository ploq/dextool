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

import logger = std.experimental.logger;

import tested;

import clang.c.index;
import clang.Cursor;
import clang.Index;
import clang.Token;
import clang.TranslationUnit;
import clang.Visitor;

import dsrcgen.cpp;

import translator.Type;

import generator.analyzer;

/// Prefix used for prepending generated code with a unique string to avoid name collisions.
alias StubPrefix = Typedef!(string, string.init, "StubPrefix");
/// Name of a C++ class/struct/namespace.
alias CppClassStructNsName = Typedef!(string, string.init, "CppNestingNs");
/// Nesting of C++ class/struct/namespace.
alias CppNesting = CppClassStructNsName[];

alias HdrFilename = Typedef!(string, string.init, "HeaderFilename");

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
    string output_header(HdrFilename filename) {
        import std.string : translate;

        dchar[dchar] table = ['.' : '_', '-' : '_'];

        ///TODO add user defined header.
        auto o = CppHModule(translate(cast(string) filename, table));
        o.content.append(this.hdr);

        return o.render;
    }

    string output_impl(HdrFilename filename) {
        ///TODO add user defined header.
        auto o = new CppModule;
        o.suppress_indent(1);
        o.include(cast(string) filename);
        logger.trace("foobar");
        o.sep(2);
        o.append(impl);

        return o.render;
    }

private:
    CppModule hdr;
    CppModule impl;

    ImplStubContext ctx;
}

private:
//TODO use the following typedefs in CppHdrImpl to avoid confusing hdr and impl.
alias CppModuleHdr = Typedef!(CppModule, CppModule.init, "CppHeader");
alias CppModuleImpl = Typedef!(CppModule, CppModule.init, "CppImplementation");
alias CppHdrImpl = Tuple!(CppModule, "hdr", CppModule, "impl");

// To avoid confusing all the different strings with the only differentiating
// fact being the variable name the idea of lots-of-typing from Haskell is
// borrowed. Type systems are awesome.
alias CppAccessSpecifier = Typedef!(CX_CXXAccessSpecifier, CX_CXXAccessSpecifier.init,
    "CppAccess");
alias CppClassName = Typedef!(string, string.init, "CppClassName");
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppType = Typedef!(string, string.init, "CppType");
alias CppVariable = Typedef!(string, string.init, "CppVariable");

//alias TypeName = Tuple!(string, "type", string, "name");
alias TypeName = Tuple!(CppType, "type", CppVariable, "name");

alias CallbackNs = Typedef!(string, string.init, "CallbackNs");
alias CallbackPrefix = Typedef!(string, string.init, "CallbackPrefix");

alias DataNs = Typedef!(string, string.init, "DataNs");
alias CallbackStruct = Typedef!(string, string.init, "CallbackStructInNs");
alias CallbackContVariable = Typedef!(TypeName, TypeName.init, "CallbackContVariable");
alias CountStruct = Typedef!(string, string.init, "CountStructInNs");
alias CountContVariable = Typedef!(TypeName, TypeName.init, "CountContVariable");
alias StaticStruct = Typedef!(string, string.init, "StaticStructInNs");
alias StaticContVariable = Typedef!(TypeName, TypeName.init, "StaticContVariable");

/** Name mangling that occurs when translating to C++ code.
 */
enum NameMangling {
    Plain, // no mangling
    Callback,
    CallCounter,
    ReturnType
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

/// Null if it was unable to convert.
auto mangleToVariable(in CppMethodName method) pure nothrow @safe {
    Nullable!CppVariable rval;

    if (find(cast(string) method, "operator") != string.init) {
        auto callback_method = cppOperatorToName(method);

        if (!callback_method.isNull)
            rval = cast(CppVariable) callback_method;
    }
    else {
        rval = cast(CppVariable) method;
    }

    return rval;
}

/// Null if it was unable to convert.
auto mangleToCallbackMethod(in CppMethodName method) pure nothrow @safe {
    Nullable!CppMethodName rval;
    // same mangle schema but different return types so resuing but in a safe
    // manner not don't affect the rest of the program.
    auto tmp = mangleToVariable(method);
    if (!tmp.isNull) {
        rval = cast(CppMethodName) tmp.get;
    }

    return rval;
}

auto mangleToCallbackStructVariable(in StubPrefix prefix, in CppClassName name) pure nothrow @safe {
    return CppVariable(cast(string) prefix ~ cast(string) name ~ "_callback");
}

/// Null if it was unable to convert.
auto mangleToReturnVariable(in CppMethodName method) pure nothrow @safe {
    Nullable!CppVariable rval;

    if (find(cast(string) method, "operator") != string.init) {
        auto callback_method = cppOperatorToName(method);

        if (!callback_method.isNull)
            rval = CppVariable(cast(string) callback_method ~ "_return");
    }

    return rval;
}

auto mangleTypeToCallbackStructType(in CppType type) pure @safe {
    import std.algorithm.searching : find;

    string r = (cast(string) type).replace("const", "");
    if (find(r, "&") != string.init) {
        r = r.replace("&", "") ~ "*";
    }

    return CppType(r.strip);
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
                    auto name = CppClassName(c.spelling);
                    (ClassTranslateContext(prefix, name)).translate(c,
                        nesting.values, hdr_impl.top.hdr, hdr_impl.top.impl);
                    nesting.push(level, CppClassStructNsName(c.spelling));
                }
                break;

                //case CXCursor_StructDecl
                //case CXCursor_FunctionDecl
            case CXCursor_Namespace:
                hdr_impl.push(level,
                    namespaceTranslator(CppClassStructNsName(c.spelling), hdr_impl.top.get));
                nesting.push(level, CppClassStructNsName(c.spelling));
                break;
            case CXCursor_CXXBaseSpecifier:
                decend = false;
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
    @disable this();

    this(StubPrefix stub_prefix, CallbackNs cb_ns, CallbackPrefix cb_prefix,
        DataNs data_ns, CallbackStruct cb_st, CountStruct cnt_st, StaticStruct st_st) {
        this.stub_prefix = stub_prefix;
        this.cb_ns = cb_ns;
        this.cb_prefix = cb_prefix;
        this.data_ns = data_ns;
        this.cb_st = cb_st;
        this.cnt_st = cnt_st;
        this.st_st = st_st;
    }

    void push(in NameMangling mangling, in TypeName tn) pure @safe nothrow {
        final switch (mangling) with (NameMangling) {
        case Callback:
            callback_vars ~= InternalType(mangling, tn);
            break;
        case CallCounter:
            cnt_vars ~= InternalType(mangling, tn);
            break;

        case Plain:
        case ReturnType:
            static_vars ~= InternalType(mangling, tn);
            break;
        }
    }

    void push(in NameMangling mangling, in CppType type, in CppVariable name) pure @safe nothrow {
        push(mangling, TypeName(type, name));
    }

    void push(in NameMangling mangling, in ref TypeName[] tn) pure @safe nothrow {
        import std.algorithm.iteration : map;
        import std.range : chain;

        tn.each!(a => push(mangling, a));
    }

    /** Number of variables stored.
     */
    @property auto length() {
        return static_vars.length + callback_vars.length + cnt_vars.length;
    }

    @property auto callbackLength() {
        return callback_vars.length;
    }

    @property auto countLength() {
        return cnt_vars.length;
    }

    @property auto staticLength() {
        return static_vars.length;
    }

    void renderCallback(T0, T1)(ref T0 hdr, ref T1 impl) {
        if (callback_vars.length == 0)
            return;

        auto st = hdr.struct_(cast(string) cb_st);
        foreach (item; callback_vars)
            with (st) {
                TypeName tn = InternalToTypeName(item);
                stmt(format("%s %s", cast(string) tn.type, cast(string) tn.name));
            }
        renderInit(TypeName(cast(CppType) cb_st, CppVariable("value")), hdr, impl);
        hdr.sep;
    }

    void renderCount(T0, T1)(ref T0 hdr, ref T1 impl) {
        if (cnt_vars.length == 0)
            return;

        auto st = hdr.struct_(cast(string) cnt_st);
        foreach (item; cnt_vars)
            with (st) {
                TypeName tn = InternalToTypeName(item);
                stmt(format("%s %s", cast(string) tn.type, cast(string) tn.name));
            }
        renderInit(TypeName(cast(CppType) cnt_st, CppVariable("value")), hdr, impl);
        hdr.sep;
    }

    void renderStatic(T0, T1)(ref T0 hdr, ref T1 impl) {
        if (static_vars.length == 0)
            return;

        auto st = hdr.struct_(cast(string) st_st);
        foreach (item; static_vars)
            with (st) {
                TypeName tn = InternalToTypeName(item);
                stmt(format("%s %s", cast(string) tn.type, cast(string) tn.name));
            }
        renderInit(TypeName(cast(CppType) st_st, CppVariable("value")), hdr, impl);
        hdr.sep;
    }

private:
    TypeName InternalToTypeName(InternalType it) pure @safe nothrow const {
        TypeName tn;

        final switch (it.mangling) with (NameMangling) {
        case Plain:
            return it.typename;
        case Callback:
            tn.type = cb_ns ~ "::" ~ cb_prefix ~ it.typename.type ~ "*";
            tn.name = it.typename.name;
            return tn;
        case CallCounter:
            tn.type = it.typename.type;
            tn.name = it.typename.name;
            return tn;
        case ReturnType:
            tn.type = it.typename.type;
            tn.name = it.typename.name ~ "_return";
            return tn;
        }
    }

    /// Init function for a struct of data.
    void renderInit(T0, T1)(TypeName tn, ref T0 hdr, ref T1 impl) {
        void doHeader(TypeName tn, ref T0 hdr) {
            hdr.func("void", "StubInit", format("%s* %s",
                cast(string) tn.type, cast(string) tn.name))[$.begin = ";",
                $.end = newline, $.noindent = true];
        }

        void doImpl(TypeName tn, ref T1 impl) {
            auto f = impl.func("void", cast(string) stub_prefix ~ "Init", tn.type ~ "* " ~ tn.name);
            with (f) {
                stmt(E("char* d") = E("static_cast<char*>")(cast(string) tn.name));
                stmt(E("char* end") = E("d") + E("sizeof")(cast(string) tn.type));
                with (for_("", "d != end", "++d")) {
                    stmt(E("*d") = 0);
                }
            }
            impl.sep;
        }

        doHeader(tn, hdr);
        doImpl(tn, impl);
    }

    alias InternalType = Tuple!(NameMangling, "mangling", TypeName, "typename");
    InternalType[] static_vars;
    InternalType[] callback_vars;
    InternalType[] cnt_vars;

    immutable StubPrefix stub_prefix;
    immutable CallbackNs cb_ns;
    immutable CallbackPrefix cb_prefix;
    immutable DataNs data_ns;
    immutable CallbackStruct cb_st;
    immutable CountStruct cnt_st;
    immutable StaticStruct st_st;
}

/// Public functions to generate callbacks for.
struct CallbackContainer {
    @disable this();

    /**
     * Params:
     *  cb_ns = namespace containing generated code for callbacks.
     *  cprefix = prefix for callback interfaces.
     */
    this(CallbackNs cb_ns, CallbackPrefix cprefix) {
        this.cb_ns = cb_ns;
        this.cprefix = cprefix;
    }

    /** Add a callback to the container.
     * Params:
     *  type = return type of the method.
     *  method = method name of the callback.
     *  params = parameters the method callback shall accept.
     */
    void push(CppType return_type, CppMethodName method, in TypeName[] params) {
        items ~= CallbackType(return_type, method, params.dup);
    }

    bool exists(CppMethodName method) {
        import std.algorithm : any;

        return items.any!(a => a.name == method);
    }

    @property auto length() {
        return items.length;
    }

    /** Generate C++ code in the provided module for all callbacks.
     * Params:
     *  data_ns = namespace to generate code in.
     *  hdr = module for generated declaration code.
     *  impl = module for generated implementation code
     */
    void renderInterfaces(ref CppModule hdr) {
        if (length == 0)
            return;

        auto ns_hdr = hdr.namespace(cast(string) cb_ns);
        ns_hdr.suppress_indent(1);
        foreach (c; items) {
            auto s = ns_hdr.struct_(cast(string) cprefix ~ cast(string) c.name);
            s[$.begin = " {", $.noindent = true];
            auto m = s.method(true, cast(string) c.return_type,
                cast(string) c.name, false, c.params.toString);
            m[$.begin = "", $.end = " = 0; ", $.noindent = true];
            m.set_indentation(1);
        }

        hdr.sep;
    }

private:
    alias CallbackType = Tuple!(CppType, "return_type", CppMethodName,
        "name", TypeName[], "params");
    CallbackType[] items;
    CallbackNs cb_ns;
    CallbackPrefix cprefix;
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
    this(StubPrefix prefix, CppClassName name) {
        this.prefix = prefix;

        CallbackNs cb_ns = prefix ~ "Callback" ~ name;
        CallbackPrefix cp = "I";
        this.data_ns = DataNs(prefix ~ "Internal" ~ name);
        CallbackStruct cb_st = prefix ~ "Callback";
        CountStruct cnt_st = prefix ~ "Counter";
        StaticStruct st_st = prefix ~ "Static";

        this.vars = VariableContainer(prefix, cb_ns, cp, data_ns, cb_st, cnt_st, st_st);
        this.callbacks = CallbackContainer(cb_ns, cp);
        this.cb_var_name = CallbackContVariable(
            TypeName(CppType(cast(string) data_ns ~ "::" ~ cast(string) cb_st),
            CppVariable(cast(string) prefix ~ cast(string) name ~ "_callback")));
        this.cnt_var_name = CountContVariable(
            TypeName(CppType(cast(string) data_ns ~ "::" ~ cast(string) cnt_st),
            CppVariable(cast(string) prefix ~ cast(string) name ~ "_cnt")));
        this.st_var_name = StaticContVariable(
            TypeName(CppType(cast(string) data_ns ~ "::" ~ cast(string) st_st),
            CppVariable(cast(string) prefix ~ cast(string) name ~ "_static")));
    }

    void translate(ref Cursor cursor, const ref CppNesting nesting,
        ref CppModule hdr, ref CppModule impl) {
        import std.array : join;

        void doTraversal() {
            auto c = Cursor(cursor);
            visit_ast!ClassTranslateContext(c, this);
        }

        void doDataStruct() {
            if (vars.length == 0)
                return;

            auto ns_hdr = hdr.namespace(cast(string) data_ns);
            ns_hdr.suppress_indent(1);
            auto ns_impl = impl.namespace(cast(string) data_ns);
            ns_impl.suppress_indent(1);

            vars.renderCallback(ns_hdr, ns_impl);
            hdr.sep;
            impl.sep;
            vars.renderCount(ns_hdr, ns_impl);
            hdr.sep;
            impl.sep;
            vars.renderStatic(ns_hdr, ns_impl);
            hdr.sep;
            impl.sep;
        }

        void doDataStructInit() {
            if (vars.length == 0)
                return;

            auto vars_getters_hdr = accessSpecifierTranslator(
                CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXPublic), this.class_code.hdr);
            this.class_code.hdr.sep;
            auto vars_hdr = accessSpecifierTranslator(
                CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXPrivate), this.class_code.hdr);
            if (vars.callbackLength > 0) {
                vars_getters_hdr.func(cast(string) cb_var_name.type ~ "&",
                    cast(string) prefix ~ "GetCallback")[$.begin = ";",
                    $.end = newline, $.noindent = true];
                vars_hdr.stmt(cast(string) cb_var_name.type ~ " " ~ cb_var_name.name);
            }
            if (vars.countLength > 0) {
                vars_getters_hdr.func(cast(string) cnt_var_name.type ~ "&",
                    cast(string) prefix ~ "GetCounter")[$.begin = ";",
                    $.end = newline, $.noindent = true];
                vars_hdr.stmt(cast(string) cnt_var_name.type ~ " " ~ cnt_var_name.name);
            }
            if (vars.staticLength > 0) {
                vars_getters_hdr.func(cast(string) st_var_name.type ~ "&",
                    cast(string) prefix ~ "GetStatic")[$.begin = ";",
                    $.end = newline, $.noindent = true];
                vars_hdr.stmt(cast(string) st_var_name.type ~ " " ~ st_var_name.name);
            }
        }

        this.top = CppHdrImpl(hdr, impl);
        this.nesting = CppClassNesting(nesting.map!(a => cast(string) a).join("::"));
        push(top);

        doTraversal();

        callbacks.renderInterfaces(hdr);
        doDataStruct();
        doDataStructInit();
    }

    /** Traverse cursor and translate a subset of kinds.
     * It defers translation of class methods to specialized translator for those.
     * The reason is that a class can have multiple interfaces it inherit from
     * and the generated stub must implement all of them.
     */
    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, depth);

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_ClassDecl:
            // Cursor sent is the root of the class so first time we descend
            // because it is the class asked of us to translate.  Further
            // ClassDecl found are nested classes. Those are taken care of by
            // other code and thus ignored.
            final switch (classdecl_used) {
            case true:
                descend = false;
                break;
            case false:
                this.classdecl_used = true;
                auto name = CppClassName(c.spelling);
                auto stubname = CppClassName(cast(string) prefix ~ name);
                push(classTranslator(prefix, nesting, name, current.get));
                class_code = current.get;
                MethodTranslateContext(stubname, access_spec).translate(c,
                    vars, callbacks, current.get);
                break;
            }
            break;
        case CXCursor_Constructor:
            push(CppHdrImpl(consumeAccessSpecificer(access_spec, current.hdr), current.impl));
            ctorTranslator(c, prefix, current.hdr, current.impl);
            descend = false;
            break;
        case CXCursor_Destructor:
            push(CppHdrImpl(consumeAccessSpecificer(access_spec, current.hdr), current.impl));
            dtorTranslator(c, prefix, vars, callbacks, current.hdr, current.impl);
            descend = false;
            break;
        case CXCursor_CXXAccessSpecifier:
            access_spec = CppAccessSpecifier(c.access.accessSpecifier);
            break;
        default:
            break;
        }
        return descend;
    }

private:
    bool classdecl_used;
    CppHdrImpl top;
    CppHdrImpl class_code; // top of the new class created.
    StubPrefix prefix;
    VariableContainer vars;
    CallbackContainer callbacks;
    CppClassNesting nesting;
    Nullable!CppAccessSpecifier access_spec;

    DataNs data_ns;
    CallbackContVariable cb_var_name;
    CountContVariable cnt_var_name;
    StaticContVariable st_var_name;
}

CppModule consumeAccessSpecificer(ref Nullable!CppAccessSpecifier access_spec, ref CppModule hdr) {
    CppModule r = hdr;

    if (!access_spec.isNull) {
        r = accessSpecifierTranslator(access_spec.get, hdr);
    }

    access_spec.nullify;
    return r;
}

/** Translate class methods to stub implementation.
 */
struct MethodTranslateContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    this(CppClassName class_name, Nullable!CppAccessSpecifier access_spec) {
        this.name = class_name;
        this.access_spec = access_spec;
    }

    void translate(ref Cursor cursor, ref VariableContainer vars,
        ref CallbackContainer callbacks, ref CppHdrImpl hdr_impl) {
        this.vars.bind(&vars);
        this.callbacks.bind(&callbacks);

        push(hdr_impl);
        visit_ast!MethodTranslateContext(cursor, this);
    }

    bool apply(Cursor c) {
        bool descend = true;
        log_node(c, depth);

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_CXXMethod:
            if (callbacks.exists(CppMethodName(c.spelling)))
                break;
            //TODO ugly move check to inside function Translator or something...
            if (c.func.isVirtual) {
                push(CppHdrImpl(consumeAccessSpecificer(access_spec, current.hdr),
                    current.impl));
            }
            functionTranslator(c, name, vars, callbacks, access_spec, current.hdr,
                current.impl);
            descend = false;
            break;
        case CXCursor_CXXAccessSpecifier:
            access_spec = CppAccessSpecifier(c.access.accessSpecifier);
            break;
        case CXCursor_CXXBaseSpecifier:
            inheritMethodTranslator(c, name, vars, callbacks, current.get);
            descend = false;
            break;
        default:
            break;
        }

        return descend;
    }

private:
    CppClassName name;

    NullableRef!VariableContainer vars;
    NullableRef!CallbackContainer callbacks;
    Nullable!CppAccessSpecifier access_spec;
}

/** Translate an access specifier to code suitable for a c++ header.
 * It is on purpuse that node is initialized to hdr. If the access specifier is
 * invalid then no harm is done by returning it.
 *
 * Params:
 *  cursor = Cursor to translate
 *  hdr = Header module to append the translation to.
 *  impl = Implementation module to append the translation to (not used).
 */
CppModule accessSpecifierTranslator(CppAccessSpecifier kind, ref CppModule hdr) {
    CppModule node = hdr;

    final switch (cast(CX_CXXAccessSpecifier) kind) with (CX_CXXAccessSpecifier) {
    case CX_CXXInvalidAccessSpecifier:
        break;
    case CX_CXXPublic:
        node = hdr.public_;
        node.suppress_indent(1);
        break;
    case CX_CXXProtected:
        node = hdr.protected_;
        node.suppress_indent(1);
        break;
    case CX_CXXPrivate:
        node = hdr.private_;
        node.suppress_indent(1);
        break;
    }

    return node;
}

CppHdrImpl classTranslator(StubPrefix prefix, CppClassNesting nesting,
    CppClassName name, ref CppHdrImpl hdr_impl) {
    auto doHeader(ref CppModule hdr) {
        auto node = hdr;
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

void ctorTranslator(Cursor c, in StubPrefix prefix, ref CppModule hdr, ref CppModule impl) {
    void doHeader(CppClassName name, in ref TypeName[] params) {
        auto p = params.toString;
        auto node = hdr.ctor(cast(string) name, p);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(CppClassName name, in ref TypeName[] params) {
        auto s_name = cast(string) name;
        auto p = params.toString;
        auto node = impl.ctor_body(s_name, p);
        impl.sep;
    }

    CppClassName name = prefix ~ c.spelling;
    auto params = parmDeclToTypeName(c);
    doHeader(name, params);
    doImpl(name, params);
}

void dtorTranslator(Cursor c, in StubPrefix prefix, ref VariableContainer vars,
    ref CallbackContainer callbacks, ref CppModule hdr, ref CppModule impl) {
    void doHeader(CppClassName name, CppMethodName callback_name) {
        auto node = hdr.dtor(c.func.isVirtual, cast(string) name);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
        hdr.sep();

        callbacks.push(CppType("void"), callback_name, TypeName[].init);
        vars.push(NameMangling.Callback, cast(CppType) callback_name,
            cast(CppVariable) callback_name);
        vars.push(NameMangling.CallCounter, CppType("unsigned"), cast(CppVariable) callback_name);
    }

    void doImpl(CppClassName name) {
        auto s_name = cast(string) name;
        auto node = impl.dtor_body(s_name);
        impl.sep;
    }

    CppClassName name = prefix ~ c.spelling.removechars("~");
    CppMethodName callback_name = "dtor" ~ c.spelling.removechars("~");

    doHeader(name, callback_name);
    doImpl(name);
}

void functionTranslator(Cursor c, in ref CppClassName class_name,
    ref VariableContainer vars, ref CallbackContainer callbacks,
    ref Nullable!CppAccessSpecifier access_spec, ref CppModule hdr, ref CppModule impl) {
    //TODO ugly... fix this aliases.
    alias toString2 = translator.Type.toString;
    alias toString = generator.stub.toString;

    void pushVarsForCallback(in TypeName[] params,
        in CppMethodName callback_method, in string return_type,
        ref VariableContainer vars, ref CallbackContainer callbacks) {
        vars.push(NameMangling.Callback, cast(CppType) callback_method,
            cast(CppVariable) callback_method);
        vars.push(NameMangling.CallCounter, CppType("unsigned"), cast(CppVariable) callback_method);

        TypeName[] p = params.map!(
            a => TypeName(mangleTypeToCallbackStructType(CppType(a.type)),
            CppVariable(callback_method ~ "_param_" ~ a.name))).array();
        vars.push(NameMangling.Plain, p);

        if (return_type.strip != "void") {
            vars.push(NameMangling.ReturnType,
                mangleTypeToCallbackStructType(CppType(return_type)),
                cast(CppVariable) callback_method);
        }

        callbacks.push(CppType(return_type), callback_method, params);
    }

    /// Extract data needed for code generation.
    void analyzeCursor(Cursor c, out TypeName[] params, out TypeKind return_type,
        out CppMethodName method, out CppMethodName callback_method_) {
        params = parmDeclToTypeName(c);
        return_type = translateTypeCursor(c);
        method = CppMethodName(c.spelling);

        auto callback_method = mangleToCallbackMethod(CppMethodName(c.spelling));
        if (callback_method.isNull) {
            logger.errorf("Generating callback function for '%s' not supported", c.spelling);
            callback_method = CppMethodName("<not supported " ~ c.spelling ~ ">");
        }
        callback_method_ = callback_method.get;
    }

    void doHeader(in TypeName[] params, in string return_type,
        in CppMethodName method, ref CppModule hdr) {
        import std.algorithm.iteration : map;

        auto node = hdr.method(c.func.isVirtual, return_type,
            cast(string) method, c.func.isConst, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(in TypeName[] params, in string return_type, ref CppModule impl) {
        auto method_name = CppMethodName(c.spelling);
        auto node = impl.method_body(return_type, cast(string) class_name,
            cast(string) method_name, c.func.isConst, params.toString);

        impl.sep;
    }

    if (!c.func.isVirtual) {
        auto loc = c.location;
        logger.infof("%s:%d:%d:%s: Skipping, not a virtual function",
            loc.file.name, loc.line, loc.column, c.spelling);
        return;
    }

    TypeName[] params;
    TypeKind return_type;
    CppMethodName method;
    CppMethodName callback_method;

    analyzeCursor(c, params, return_type, method, callback_method);
    pushVarsForCallback(params, callback_method, toString2(return_type), vars, callbacks);

    doHeader(params, toString2(return_type), method, hdr);
    doImpl(params, toString2(return_type), impl);
}

CppHdrImpl namespaceTranslator(CppClassStructNsName nest, ref CppHdrImpl hdr_impl) {
    CppModule doHeader(ref CppModule hdr) {
        auto r = hdr.namespace(cast(string) nest);
        r.suppress_indent(1);
        hdr.sep;
        return r;
    }

    CppModule doImpl(ref CppModule impl) {
        auto r = impl.namespace(cast(string) nest);
        r.suppress_indent(1);
        impl.sep;
        return r;
    }

    return CppHdrImpl(doHeader(hdr_impl.hdr), doImpl(hdr_impl.impl));
}

void inheritMethodTranslator(ref Cursor cursor, in CppClassName name,
    ref VariableContainer vars, ref CallbackContainer callbacks, ref CppHdrImpl hdr_impl) {
    //TODO ugly hack. dunno what it should be so for now forcing to public.
    Nullable!CppAccessSpecifier access_spec;
    access_spec = CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXPublic);

    log_node(cursor, 0);
    foreach (parent, child; cursor.all) {
        log_node(parent, 0);
        log_node(child, 0);

        auto p = parent.definition;

        switch (parent.kind) with (CXCursorKind) {
        case CXCursor_TypeRef:
            log_node(p, 1);
            MethodTranslateContext(name, access_spec).translate(p, vars, callbacks,
                hdr_impl);
            break;
        default:
        }
    }
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
        logger.trace(type_spelling, "|", type, "|", param.spelling, "|", param.type.spelling);
        params ~= TypeName(CppType(toString3(type)), CppVariable(param.spelling));
    }

    logger.trace(params);
    return params;
}

/// Convert a vector of TypeName to string pairs.
auto toStrings(in TypeName[] vars) pure @safe nothrow {
    string[] params;

    foreach (tn; vars) {
        params ~= cast(string) tn.type ~ " " ~ cast(string) tn.name;
    }

    return params;
}

/// Convert a vector of TypeName to a comma separated string.
auto toString(in TypeName[] vars) pure @safe nothrow {
    auto params = vars.toStrings;
    return join(params, ", ");
}
