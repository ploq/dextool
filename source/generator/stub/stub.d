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
import generator.stub.misc;

package:

CppModule consumeAccessSpecificer(ref CppAccessSpecifier access_spec, ref CppModule hdr) {
    hdr = accessSpecifierTranslator(access_spec, hdr);

    access_spec = CX_CXXAccessSpecifier.CX_CXXInvalidAccessSpecifier;
    return hdr;
}

/** Translate an access specifier to code suitable for a c++ header.
 * It is on purpuse that node is initialized to hdr. If the access specifier is
 * invalid then no harm is done by returning it.
 *
 * Params:
 *  kind = type of access specifier (public, protected, private).
 *  hdr = Header module to append the translation to.
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
