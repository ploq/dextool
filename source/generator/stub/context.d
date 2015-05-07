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
module generator.stub.context;

import std.algorithm : among, map;
import std.array : join;
import std.conv : to;
import std.typecons : TypedefType, NullableRef;

import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;

import generator.analyzer : visit_ast, IdStack, log_node, VisitNodeModule;
import generator.stub.types;
import generator.stub.stub;
import generator.stub.containers;
import generator.stub.misc;

class StubContext {
    /**
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     */
    this(StubPrefix prefix, HdrFilename filename) {
        this.filename = filename;
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
    string output_header(HdrFilename out_filename) {
        import std.string : translate;

        dchar[dchar] table = ['.' : '_', '-' : '_'];

        ///TODO add user defined header.
        auto o = CppHModule(translate(cast(string) out_filename, table));
        o.content.include(cast(string) filename);
        o.content.sep(2);
        o.content.append(this.hdr);

        return o.render;
    }

    string output_impl(HdrFilename filename) {
        ///TODO add user defined header.
        auto o = new CppModule;
        o.suppress_indent(1);
        o.include(cast(string) filename);
        o.sep(2);
        o.append(impl);

        return o.render;
    }

private:
    CppModule hdr;
    CppModule impl;

    ImplStubContext ctx;
    HdrFilename filename;
}

package:

/// Traverse the AST and generate a stub by filling the CppModules with data.
struct ImplStubContext {

    /** Context for total stubbing of a c++ header file.
     *
     * Params:
     *  prefix = prefix to use for the name of the stub classes.
     *  hdr = C++ code for a header for the stub
     *  impl = C++ code for the implementation of the stub
     */
    this(StubPrefix prefix, CppModule hdr, CppModule impl) {
        this.prefix = prefix;
        this.hdr = hdr;
        hdr.suppress_indent(1);
        this.impl = impl;
        impl.suppress_indent(1);
        hdr_impl.push(0, CppHdrImpl(hdr, impl));
        access_spec.push(0, CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXInvalidAccessSpecifier));
    }

    void incr() {
        this.level++;
    }

    void decr() {
        nesting.pop(level);
        hdr_impl.pop(level);
        access_spec.pop(level);
        this.level--;
    }

    bool apply(Cursor c) {
        log_node(c, this.level);
        bool decend = true;

        with (CXCursorKind) {
            switch (c.kind) {
            case CXCursor_ClassDecl:
                if (c.isDefinition
                        && access_spec.top.get.among(
                        CX_CXXAccessSpecifier.CX_CXXInvalidAccessSpecifier,
                        CX_CXXAccessSpecifier.CX_CXXPublic)) {
                    logger.trace("creating stub");
                    logger.trace(
                        access_spec.values.map!(
                        a => to!string(cast(TypedefType!CppAccessSpecifier) a)).join(", "));
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
            case CXCursor_CXXAccessSpecifier:
                // affects classes on the same level so therefor modifying level by pushing it up.
                access_spec.push(level - 1, CppAccessSpecifier(c.access.accessSpecifier));
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
    IdStack!(int, CppAccessSpecifier) access_spec;
}

/** Translate a ClassDecl to a stub implementation.
 *
 * The generate stub implementation have an interface that the user can control
 * the data flow from stub -> SUT.
 */
struct ClassTranslateContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    @disable this();

    /** Context for stubbing a class with a specific prefix.
     * Params:
     *  prefix = prefix to use for the name of the stub class.
     *  name = name of the c++ class being stubbed.
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
