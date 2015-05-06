/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.stub.stub;

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
import generator.stub.types;
import generator.stub.containers;
import generator.stub.misc;

version (unittest) {
    shared static this() {
        import std.exception;

        enforce(runUnitTests!(generator.stub.stub)(new ConsoleTestResultWriter),
            "Unit tests failed.");
    }
}

package:

/** Translate a ClassDecl to a stub implementation.
 *
 * The generate stub implementation have an interface that the user can control
 * the data flow from stub -> SUT.
 */
struct ClassTranslateContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    @disable this();
    /**
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     */
    this(StubPrefix prefix, CppClassName name) {
        this.prefix = prefix;
        this.name = name;

        CallbackNs cb_ns = prefix ~ "Callback" ~ name;
        CallbackPrefix cp = "I";
        this.data_ns = StubNs(prefix ~ "Internal" ~ name);
        CallbackStruct cb_st = prefix ~ "Callback";
        CountStruct cnt_st = prefix ~ "Counter";
        StaticStruct st_st = prefix ~ "Static";

        this.vars = VariableContainer(prefix, cb_ns, cp, data_ns, cb_st, cnt_st, st_st);
        this.callbacks = CallbackContainer(cb_ns, cp);
        ///TODO refactore to using the mangle functions for _callback, _cnt and _static.
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

        void doTraversal(ref ClassTranslateContext ctx, CppHdrImpl top) {
            ctx.push(top);
            auto c = Cursor(cursor);
            visit_ast!ClassTranslateContext(c, this);
        }

        auto top = CppHdrImpl(hdr, impl);
        auto internal = CppHdrImpl(hdr.base, impl.base);
        internal.hdr.suppress_indent(1);
        internal.impl.suppress_indent(1);
        auto stub = CppHdrImpl(hdr.base, impl.base);
        stub.hdr.suppress_indent(1);
        stub.impl.suppress_indent(1);
        this.nesting = CppClassNesting(nesting.map!(a => cast(string) a).join("::"));

        doTraversal(this, stub);

        callbacks.renderInterfaces(internal.hdr);
        doDataStruct(internal.hdr, internal.impl);
        doDataStructInit(prefix, CppClassName(prefix ~ name), cb_var_name,
            cnt_var_name, st_var_name, vars, this.class_code.hdr, stub.impl);
        doCtorBody(data_ns, prefix, name, ctor_code);
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
                ///TODO change to using the name mangling function.
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
            ctorTranslator(c, prefix, current.hdr, current.impl, ctor_code);
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
    void doDataStruct(ref CppModule hdr, ref CppModule impl) {
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

    void doDataStructInitHelper(const CppClassName class_name, const TypeName tn,
        const CppMethodName method, ref CppModule pub_hdr, ref CppModule priv_hdr,
        ref CppModule impl) {
        auto type = cast(string) tn.type;
        auto return_type = cast(string) tn.type ~ "&";
        auto name = cast(string) tn.name;
        auto method_ = cast(string) method;
        auto var_name = type ~ " " ~ name;

        pub_hdr.func(return_type, method_)[$.begin = ";", $.end = newline, $.noindent = true];
        priv_hdr.stmt(var_name);

        with (impl.method_body(return_type, cast(string) class_name, method_, false)) {
            return_("this->" ~ name);
        }
        impl.sep;
    }

    void doDataStructInit(const StubPrefix prefix, const CppClassName class_name,
        const CallbackContVariable cb_var_name,
        const CountContVariable cnt_var_name,
        const StaticContVariable st_var_name, VariableContainer vars,
        ref CppModule hdr, ref CppModule impl) {
        if (vars.length == 0)
            return;

        auto vars_getters_hdr = accessSpecifierTranslator(
            CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXPublic), hdr);
        hdr.sep;
        auto vars_hdr = accessSpecifierTranslator(
            CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXPrivate), hdr);
        if (vars.callbackLength > 0) {
            doDataStructInitHelper(class_name, cast(TypeName) cb_var_name,
                CppMethodName(cast(string) prefix ~ "GetCallback"),
                vars_getters_hdr, vars_hdr, impl);
        }
        if (vars.countLength > 0) {
            doDataStructInitHelper(class_name, cast(TypeName) cnt_var_name,
                CppMethodName(cast(string) prefix ~ "GetCounter"), vars_getters_hdr,
                vars_hdr, impl);
        }
        if (vars.staticLength > 0) {
            doDataStructInitHelper(class_name, cast(TypeName) st_var_name,
                CppMethodName(cast(string) prefix ~ "GetStatic"), vars_getters_hdr,
                vars_hdr, impl);
        }
    }

    void doCtorBody(const StubNs stub_ns, const StubPrefix prefix,
        const CppClassName name, CppModule[] ctor_code) {
        if (vars.length == 0)
            return;
        // c'tors must all call the init functions for the data structures.

        string init_ = cast(string) stub_ns ~ "::StubInit";
        foreach (impl; ctor_code) {
            if (vars.callbackLength > 0) {
                impl.stmt(E(init_)("&" ~ cast(string) mangleToCallbackStructVariable(prefix,
                    name)));
            }
            if (vars.countLength > 0) {
                impl.stmt(E(init_)("&" ~ cast(string) mangleToCountStructVariable(prefix,
                    name)));
            }
            if (vars.staticLength > 0) {
                impl.stmt(E(init_)("&" ~ cast(string) mangleToStaticStructVariable(prefix,
                    name)));
            }
        }
    }

private:
    bool classdecl_used;
    CppHdrImpl class_code; // top of the new class created.
    CppModule[] ctor_code; // delayed content creation for c'tors to after analyze.
    immutable StubPrefix prefix;
    immutable CppClassName name;
    CppClassNesting nesting;

    VariableContainer vars;
    CallbackContainer callbacks;
    CppAccessSpecifier access_spec;

    immutable StubNs data_ns;
    immutable CallbackContVariable cb_var_name;
    immutable CountContVariable cnt_var_name;
    immutable StaticContVariable st_var_name;
}

CppModule consumeAccessSpecificer(ref CppAccessSpecifier access_spec, ref CppModule hdr) {
    hdr = accessSpecifierTranslator(access_spec, hdr);

    access_spec = CX_CXXAccessSpecifier.CX_CXXInvalidAccessSpecifier;
    return hdr;
}

/** Translate class methods to stub implementation.
 */
struct MethodTranslateContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    this(CppClassName class_name, CppAccessSpecifier access_spec) {
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
            functionTranslator(c, name, vars, callbacks, current.hdr, current.impl);
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
    CppAccessSpecifier access_spec;
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

void ctorTranslator(Cursor c, const StubPrefix prefix, ref CppModule hdr,
    ref CppModule impl, ref CppModule[] ctor_code) {
    void doHeader(CppClassName name, const ref TypeName[] params) {
        auto p = params.toString;
        auto node = hdr.ctor(cast(string) name, p);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(const CppClassName name, const TypeName[] params, ref CppModule[] ctor_code) {
        auto s_name = cast(string) name;
        auto p = params.toString;
        auto node = impl.ctor_body(s_name, p);
        ctor_code ~= node;
        impl.sep;
    }

    CppClassName name = prefix ~ c.spelling;
    auto params = parmDeclToTypeName(c);
    doHeader(name, params);
    doImpl(name, params, ctor_code);
}

void dtorTranslator(Cursor c, const StubPrefix prefix, ref VariableContainer vars,
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

    void doImpl(const CppClassName name, const CppClassName stub_name,
        const CppMethodName callback_name) {
        auto s_name = cast(string) stub_name;
        auto node = impl.dtor_body(s_name);

        string name_ = cast(string) name;
        ///TODO refactore to using mangle functions.
        with (node) {
            stmt(E(s_name ~ "_cnt").e("dtor" ~ name_) ~ E("++"));
            sep(2);
            with (if_(E(s_name ~ "_callback").e("dtor" ~ name_) ~ E(" != 0"))) {
                stmt(E(s_name ~ "_callback").e("dtor" ~ name_) ~ E("->") ~ E("dtor" ~ name_)(""));
            }
        }
        impl.sep;
    }

    CppClassName name = c.spelling.removechars("~");
    CppClassName stub_name = prefix ~ name;
    CppMethodName callback_name = "dtor" ~ name;

    doHeader(stub_name, callback_name);
    doImpl(name, stub_name, callback_name);
}

void functionTranslator(Cursor c, const CppClassName class_name,
    ref VariableContainer vars, ref CallbackContainer callbacks, ref CppModule hdr,
    ref CppModule impl) {
    //TODO ugly... fix this aliases.
    alias toString2 = translator.Type.toString;
    alias toString = generator.stub.stub.toString;

    void pushVarsForCallback(const TypeName[] params,
        const CppMethodName callback_method, const string return_type,
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
        foreach (idx, tn; params) {
            params[idx] = genRandomName(tn, idx);
        }
        return_type = translateTypeCursor(c);
        method = CppMethodName(c.spelling);

        auto callback_method = mangleToCallbackMethod(CppMethodName(c.spelling));
        if (callback_method.isNull) {
            logger.errorf("Generating callback function for '%s' not supported", c.spelling);
            callback_method = CppMethodName("<not supported " ~ c.spelling ~ ">");
        }
        callback_method_ = callback_method.get;
    }

    void doHeader(const TypeName[] params, const string return_type,
        const CppMethodName method, ref CppModule hdr) {
        import std.algorithm.iteration : map;

        auto node = hdr.method(c.func.isVirtual, return_type,
            cast(string) method, c.func.isConst, params.toString);
        node[$.begin = "", $.end = ";" ~ newline, $.noindent = true];
    }

    void doImpl(const TypeName[] params, const string return_type,
        const CppClassName class_name, const CppMethodName method,
        const CppMethodName callback_method, ref CppModule impl) {
        import std.algorithm : findAmong, map;

        auto helper_params(TypeName a) {
            string type_ = cast(string) a.type;
            if (findAmong(type_, ['*', '&']).length != 0) {
                //TODO how can this be done with ranges?
                if (type_.startsWith("const")) {
                    type_ = type_[5 .. $ - 1].strip;
                }
                return E("const_cast<" ~ type_ ~ "*>")("&" ~ cast(string) a.name);
            }
            return cast(string) a.name;
        }

        auto helper_return(string return_type) {
            string star;
            if (findAmong(return_type, ['&']).length != 0) {
                star = "*";
            }
            logger.trace(return_type, " ", star);

            return "return %s%s_static.%s_return".format(star,
                cast(string) class_name, cast(string) callback_method);
        }

        auto func = impl.method_body(return_type, cast(string) class_name,
            cast(string) method, c.func.isConst, params.toString);
        with (func) {
            stmt("%s_cnt.%s++".format(cast(string) class_name, cast(string) callback_method));
            foreach (a; params) {
                stmt("%s_static.%s_param_%s = %s".format(cast(string) class_name,
                    cast(string) callback_method, cast(string) a.name, helper_params(a)));
            }
            sep(2);

            string sparams = params.map!(a => cast(string) a.name).join(", ");
            if (return_type == "void") {
                with (if_("%s_callback.%s != 0".format(cast(string) class_name,
                        cast(string) callback_method))) {
                    stmt("%s_callback.%s->%s(%s)".format(cast(string) class_name,
                        cast(string) callback_method, cast(string) callback_method,
                        sparams));
                }
            }
            else {
                with (if_("%s_callback.%s == 0".format(cast(string) class_name,
                        cast(string) callback_method))) {
                    stmt(helper_return(return_type));
                }
                with (else_()) {
                    stmt("return %s_callback.%s->%s(%s)".format(cast(string) class_name,
                        cast(string) callback_method, cast(string) callback_method,
                        sparams));
                }
            }

        }

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
    doImpl(params, toString2(return_type), class_name, method, callback_method, impl);
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

void inheritMethodTranslator(ref Cursor cursor, const CppClassName name,
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
