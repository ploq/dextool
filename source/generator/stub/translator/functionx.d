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
module generator.stub.translator.functionx;

import std.algorithm : map, startsWith;
import std.array : array;
import std.conv : to;
import std.string : removechars;

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;

import translator.Type;

import generator.stub.types;
import generator.stub.containers;
import generator.stub.mangling;
import generator.stub.misc;

import tested;

version (unittest) {
    shared static this() {
        import std.exception;

        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        enforce(
            runUnitTests!(generator.stub.translator.functionx)(new ConsoleTestResultWriter),
            "Unit tests failed.");
    }
}

void functionTranslator(Cursor c, const CppClassName class_name,
    ref VariableContainer vars, ref CallbackContainer callbacks, ref CppModule hdr,
    ref CppModule impl) {

    if (!c.func.isVirtual) {
        auto loc = c.location;
        logger.warningf("%s:%d:%d:%s: Skipping, not a virtual function",
            loc.file.name, loc.line, loc.column, c.spelling);
        logger.trace(clang.Cursor.abilities(c.func));
        return;
    }

    TypeName[] params;
    TypeKind return_type;
    CppMethodName method;
    CppMethodName callback_method;

    analyzeCursor(c, params, return_type, method, callback_method);
    string return_type_ = translator.Type.toString(return_type);

    pushVarsForCallback(params, callback_method, return_type_, vars, callbacks);

    doHeader(c.func.isVirtual, c.func.isConst, params, return_type_, method, hdr);
    doImpl(c.func.isConst, params, return_type_, class_name, method, callback_method,
        impl);
}

private:

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
            mangleTypeToCallbackStructType(CppType(return_type)), cast(CppVariable) callback_method);
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
    return_type = translateType(c.func.resultType);
    method = CppMethodName(c.spelling);

    auto callback_method = mangleToCallbackMethod(CppMethodName(c.spelling));
    if (callback_method.isNull) {
        logger.errorf("Generating callback function for '%s' not supported", c.spelling);
        callback_method = CppMethodName("<not supported " ~ c.spelling ~ ">");
    }
    callback_method_ = callback_method.get;
}

void doHeader(bool is_virtual, bool is_const, const TypeName[] params,
    const string return_type, const CppMethodName method, ref CppModule hdr) {
    import std.algorithm.iteration : map;

    string method_ = cast(string) method;

    auto node = hdr.method(is_virtual, return_type, method_, is_const, params.toString);
}

auto castAndStoreValue(TypeName a) @safe {
    //TODO change TypeName to use TypeKind instead of CppType.
    import std.algorithm : canFind;

    string type_ = cast(string) a.type;
    string get_ptr;
    bool do_const_cast;

    if (type_.canFind('&')) {
        get_ptr = "&";
        if (type_.startsWith("const")) {
            type_ = type_[5 .. $ - 1].strip;
            do_const_cast = true;
        }
    }
    else if (type_.canFind('*')) {
        if (type_.startsWith("const")) {
            type_ = type_[5 .. $ - 1].strip;
            do_const_cast = true;
        }
    }

    if (do_const_cast) {
        return E("const_cast<" ~ type_ ~ "*>")(get_ptr ~ cast(string) a.name);
    }
    return get_ptr ~ cast(string) a.name;
}

@name("Test helper for parameter casting when storing parameters")
unittest {
    auto rval = castAndStoreValue(TypeName(CppType("int"), CppVariable("bar")));
    assert(rval == "bar", rval);
}

@name("Test helper for parameter casting of ref and ptr")
unittest {
    auto rval = castAndStoreValue(TypeName(CppType("int*"), CppVariable("bar")));
    assert(rval == "bar", to!string(__LINE__) ~ rval);

    rval = castAndStoreValue(TypeName(CppType("int&"), CppVariable("bar")));
    assert(rval == "&bar", to!string(__LINE__) ~ rval);
}

@name("Test helper for const parameter casting of ref and ptr")
unittest {
    auto rval = castAndStoreValue(TypeName(CppType("const int*"), CppVariable("bar")));
    assert(rval == "const_cast<int*>(bar)", rval);

    rval = castAndStoreValue(TypeName(CppType("const int&"), CppVariable("bar")));
    assert(rval == "const_cast<int*>(&bar)", rval);
}

auto makeCppReturnFromStruct(string return_type, const CppClassName class_name,
    const CppMethodName callback_method) {
    import std.algorithm : findAmong;

    string star;
    if (findAmong(return_type, ['&']).length != 0) {
        star = "*";
    }

    return "return %s%s_static.%s_return".format(star, cast(string) class_name,
        cast(string) callback_method);
}

@name("Test maker for generating code returning a static value")
unittest {
    auto rval = makeCppReturnFromStruct("int", CppClassName("Foo"), CppMethodName("Bar"));
    assert(rval == "return Foo_static.Bar_return", rval);

    rval = makeCppReturnFromStruct("int&", CppClassName("Foo"), CppMethodName("Bar"));
    assert(rval == "return *Foo_static.Bar_return", rval);
}

void doImpl(bool is_const, const TypeName[] params, const string return_type,
    const CppClassName class_name, const CppMethodName method,
    const CppMethodName callback_method, ref CppModule impl) {
    import std.algorithm : findAmong, map;

    string class_name_ = cast(string) class_name;
    string callback_method_ = cast(string) callback_method;

    auto func = impl.method_body(return_type, class_name_, cast(string) method,
        is_const, params.toString);
    with (func) {
        stmt("%s_cnt.%s++".format(class_name_, callback_method_));
        // store parameters for the function in the static storage to be used by the user in test cases.
        foreach (a; params) {
            stmt("%s_static.%s_param_%s = %s".format(class_name_,
                callback_method_, cast(string) a.name, a.castAndStoreValue));
        }
        sep(2);

        string sparams = params.map!(a => cast(string) a.name).join(", ");
        if (return_type == "void") {
            with (if_("%s_callback.%s != 0".format(class_name_, callback_method_))) {
                stmt("%s_callback.%s->%s(%s)".format(class_name_,
                    callback_method_, callback_method_, sparams));
            }
        }
        else {
            with (if_("%s_callback.%s == 0".format(class_name_, callback_method_))) {
                stmt(makeCppReturnFromStruct(return_type, class_name, callback_method));
            }
            with (else_()) {
                stmt("return %s_callback.%s->%s(%s)".format(class_name_,
                    callback_method_, callback_method_, sparams));
            }
        }

    }

    impl.sep;
}
