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
module generator.stub.containers;

import std.algorithm : each;
import std.ascii : newline;
import std.string : format;
import std.typecons : Tuple;

import logger = std.experimental.logger;

import dsrcgen.cpp;

import generator.stub.types;
import generator.stub.misc;

package:

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
        StubNs data_ns, CallbackStruct cb_st, CountStruct cnt_st, StaticStruct st_st) {
        this.stub_prefix = stub_prefix;
        this.cb_ns = cb_ns;
        this.cb_prefix = cb_prefix;
        this.data_ns = data_ns;
        this.cb_st = cb_st;
        this.cnt_st = cnt_st;
        this.st_st = st_st;
    }

    void push(const NameMangling mangling, const TypeName tn) pure @safe nothrow {
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

    void push(const NameMangling mangling, const CppType type, const CppVariable name) pure @safe nothrow {
        push(mangling, TypeName(type, name));
    }

    void push(const NameMangling mangling, const ref TypeName[] tn) pure @safe nothrow {
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
                stmt(E("char* d") = E("reinterpret_cast<char*>")(cast(string) tn.name));
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
    immutable StubNs data_ns;
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
    void push(CppType return_type, CppMethodName method, const TypeName[] params) {
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
