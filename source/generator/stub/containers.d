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

private:

import std.algorithm : each;
import std.ascii : newline;
import std.string : format;
import std.typecons : Tuple;

import logger = std.experimental.logger;

import dsrcgen.cpp;

import generator.stub.types;
import generator.stub.misc;
import generator.stub.mangling;

import tested;

version (unittest) {
    shared static this() {
        import std.exception;

        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        enforce(runUnitTests!(generator.stub.containers)(new ConsoleTestResultWriter),
            "Unit tests failed.");
    }
}

package:

/** Variables discovered during traversal of AST that data storage in the stub.
 * A common case is pointers to callbacks and parameters.
 *
 * NameMangling affects how the types and variables are translated to C++ code.
 * See translate() for details.
 *
 * Chose to not use the built-in associative array because it doesn't preserve
 * the order.
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
        StubNs data_ns, CppClassName class_name) {
        import std.string : toLower;

        this.stub_prefix = stub_prefix;
        this.stub_prefix_lower = StubPrefix((cast(string) stub_prefix).toLower);
        this.cb_ns = cb_ns;
        this.cb_prefix = cb_prefix;
        this.data_ns = data_ns;
        this.class_name = class_name;
    }

    void push(const NameMangling mangling, const TypeName tn, const CppMethodName grouping) pure @safe nothrow {
        import std.algorithm : canFind;

        if (!groups.canFind(grouping))
            groups ~= grouping;
        vars ~= InternalType(mangling, tn, grouping);
    }

    void push(const NameMangling mangling, const CppType type,
        const CppVariable name, const CppMethodName grouping) pure @safe nothrow {
        push(mangling, TypeName(type, name), grouping);
    }

    void push(const NameMangling mangling, const ref TypeName[] tn, const CppMethodName grouping) pure @safe nothrow {
        tn.each!(a => push(mangling, a, grouping));
    }

    /// Number of variables stored.
    @property auto length() {
        return vars.length;
    }

    void render(T0, T1)(ref T0 hdr, ref T1 impl) {
        auto hdr_structs = hdr.base;
        auto impl_structs = impl.base;
        hdr_structs.suppress_indent(1);
        impl_structs.suppress_indent(1);

        auto impl_data = impl.base;
        impl_data.suppress_indent(1);

        // create data class containing the stub interface
        auto data_class = mangleToStubDataClass(stub_prefix);
        auto hdr_data = hdr.class_(data_class.str);
        auto hdr_data_pub = hdr_data.public_;
        hdr_data.sep;
        auto hdr_data_priv = hdr_data.private_;
        hdr_data_pub.suppress_indent(1);
        hdr_data_priv.suppress_indent(1);

        with (hdr_data_pub) {
            ctor(data_class.str);
            dtor(data_class.str);
            sep;
        }

        CppModule ctor_init;
        with (impl_data) {
            ctor_init = ctor_body(data_class.str);
            sep;
            dtor_body(data_class.str);
            sep;
        }

        // fill with data
        foreach (g; groups) {
            renderGroup(g, hdr_structs, impl_structs, ctor_init);
            renderDataFunc(g, hdr_data_pub, hdr_data_priv, impl_data);
        }
    }

    private void renderGroup(T0, T1)(CppMethodName group, ref T0 hdr,
        ref T1 impl, ref T1 ctor_init_impl) {
        import std.string : toLower;

        CppType st_type = stub_prefix ~ group;
        auto st = hdr.struct_(st_type.str);
        foreach (item; vars) {
            if (item.group == group) {
                TypeName tn = InternalToTypeName(item);
                st.stmt(format("%s %s", tn.type.str, tn.name.str));
            }
        }
        renderInit(TypeName(st_type, CppVariable("value")), group, hdr, impl, ctor_init_impl);
        hdr.sep;
    }

    private void renderDataFunc(T0, T1, T2)(CppMethodName group, ref T0 hdr_pub,
        ref T1 hdr_priv, ref T2 impl) {
        import std.algorithm : find;

        auto internal = vars.find!(a => a.mangling == NameMangling.Callback && a.group == group);
        if (internal.length == 0) {
            logger.errorf("No callback variable for group '%s'", group.str);
            return;
        }
        auto tn = internal[0].typename;

        auto struct_type = mangleToStubStructType(stub_prefix, group, class_name);
        auto variable = mangleToStubDataClassInternalVariable(stub_prefix,
            CppMethodName(tn.name.str));

        hdr_pub.method(false, E(struct_type.str) ~ E("&"), tn.name.str, false);
        hdr_priv.stmt(E(struct_type.str) ~ "" ~ E(variable.str));

        auto data_name = mangleToStubDataClass(stub_prefix);
        with (impl.method_body(struct_type.str ~ "&", data_name.str, tn.name.str, false)) {
            return_(E(variable.str));
        }
        impl.sep;
    }

private:
    TypeName InternalToTypeName(InternalType it) pure @safe nothrow const {
        TypeName tn;

        tn.name = mangleToStubStructMember(stub_prefix_lower, it.mangling, tn.name);

        final switch (it.mangling) with (NameMangling) {
        case Plain:
            return it.typename;
        case Callback:
            tn.type = cb_ns ~ "::" ~ cb_prefix ~ it.typename.type ~ "*";
            return tn;
        case CallCounter:
            tn.type = it.typename.type;
            return tn;
        case ReturnType:
            tn.type = it.typename.type;
            return tn;
        }
    }

    /// Init function for a struct of data.
    void renderInit(T0, T1)(TypeName tn, CppMethodName method, ref T0 hdr,
        ref T1 impl, ref T1 ctor_init_impl) {
        void doHeader(TypeName tn, ref T0 hdr) {
            hdr.func("void", "StubInit", format("%s* %s", tn.type.str, tn.name.str))[$.begin = ";",
                $.end = newline, $.noindent = true];
        }

        void doImpl(TypeName tn, ref T1 impl, ref T1 ctor_init_impl) {
            auto init_func = stub_prefix.str ~ "Init";

            auto f = impl.func("void", init_func, tn.type ~ "* " ~ tn.name);
            with (f) {
                stmt(E("char* d") = E("reinterpret_cast<char*>")(tn.name.str));
                stmt(E("char* end") = E("d") + E("sizeof")(tn.type.str));
                with (for_("", "d != end", "++d")) {
                    stmt(E("*d") = 0);
                }
            }
            impl.sep;

            ctor_init_impl.stmt(
                E(init_func)("&" ~ mangleToStubDataClassInternalVariable(stub_prefix,
                method).str));
        }

        doHeader(tn, hdr);
        doImpl(tn, impl, ctor_init_impl);
    }

    alias InternalType = Tuple!(NameMangling, "mangling", TypeName, "typename",
        CppMethodName, "group");
    InternalType[] vars;
    CppMethodName[] groups;

    immutable StubPrefix stub_prefix;
    immutable StubPrefix stub_prefix_lower;
    immutable CallbackNs cb_ns;
    immutable CallbackPrefix cb_prefix;
    immutable StubNs data_ns;
    immutable CppClassName class_name;
}

/// Container of functions to generate callbacks for.
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
     *  return_type = return type of the method.
     *  method = method name of the callback.
     *  params = parameters the method callback shall accept.
     */
    void push(CppType return_type, CppMethodName method, const TypeName[] params) {
        items ~= CallbackType(return_type, method, params.dup);
    }

    /** Add a callback to the container.
     * Params:
     *  return_type = return type of the method.
     *  method = method name of the callback.
     *  params = parameters the method callback shall accept.
     */
    void push(CppType return_type, CppMethodName method, const TypeKindVariable[] params) {
        import std.algorithm : map;
        import std.array : array;

        TypeName[] tmp = params.map!(a => TypeName(CppType(a.type.toString), a.name)).array();

        items ~= CallbackType(return_type, method, tmp);
    }

    ///TODO change to using an ID for the method.
    /// One proposal is to traverse the function inherit hierarchy to find the root.
    bool exists(CppMethodName method, const TypeName[] params) {
        import std.algorithm : any;

        string p = params.toString;

        return items.any!(a => a.name == method && a.params.toString == p);
    }

    @property auto length() {
        return items.length;
    }

    /** Generate C++ code in the provided module for all callbacks.
     * Params:
     *  hdr = module for generated declaration code.
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

@name("Test CallbackContainer length")
unittest {
    CallbackContainer cb = CallbackContainer(CallbackNs("foo"), CallbackPrefix("Stub"));
    assert(cb.length == 0, "expected 0, actual " ~ to!string(cb.length));

    cb.push(CppType("void"), CppMethodName("smurf"), TypeName[].init);
    assert(cb.length == 1, "expected 1, actual " ~ to!string(cb.length));
}

@name("Test CallbackContainer exists")
unittest {
    CallbackContainer cb = CallbackContainer(CallbackNs("foo"), CallbackPrefix("Stub"));
    cb.push(CppType("void"), CppMethodName("smurf"), TypeName[].init);

    assert(cb.exists(CppMethodName("smurf"), TypeName[].init), "expected true");
}

@name("Test CallbackContainer rendering")
unittest {
    CallbackContainer cb = CallbackContainer(CallbackNs("Foo"), CallbackPrefix("Stub"));

    cb.push(CppType("void"), CppMethodName("smurf"), TypeName[].init);
    auto m = new CppModule;
    m.suppress_indent(1);

    cb.renderInterfaces(m);

    auto rval = m.render;
    auto exp = "namespace Foo {
struct Stubsmurf { virtual void smurf() = 0; };
} //NS:Foo

";

    assert(rval == exp, rval);
}
