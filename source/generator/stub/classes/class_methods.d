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
module generator.stub.classes.class_methods;

import std.typecons : TypedefType, NullableRef, Nullable;

import clang.c.index;
import clang.Cursor;

import generator.analyzer : visitAst, IdStack, logNode, VisitNodeModule;
import generator.stub.containers : CallbackContainer, VariableContainer;
import generator.stub.misc : parmDeclToTypeName;
import generator.stub.types;
import generator.stub.classes.access : consumeAccessSpecificer;
import generator.stub.classes.functionx;

/** Translate class methods to stub implementation.
 */
struct MethodContext {
    VisitNodeModule!CppHdrImpl visitor_stack;
    alias visitor_stack this;

    this(StubPrefix prefix, CppClassName class_name,
        CppAccessSpecifier access_spec, OnlyStubVirtual only_virt) {
        this.prefix = prefix;
        this.name = class_name;
        this.access_spec = access_spec;
        this.only_stub_virtual = only_virt;
    }

    void translate(ref Cursor cursor, ref VariableContainer vars,
        ref CallbackContainer callbacks, ref CppHdrImpl hdr_impl) {
        this.vars.bind(&vars);
        this.callbacks.bind(&callbacks);

        push(hdr_impl);
        visitAst!MethodContext(cursor, this);
    }

    bool apply(Cursor c) {
        bool descend = true;
        logNode(c, depth);

        switch (c.kind) with (CXCursorKind) {
        case CXCursor_CXXMethod:
            if (callbacks.exists(CppMethodName(c.spelling), c.parmDeclToTypeName))
                break;
            //TODO ugly move check to inside function Translator or something...
            if (c.func.isVirtual || cast(bool) only_stub_virtual == false) {
                push(CppHdrImpl(consumeAccessSpecificer(access_spec, current.hdr),
                    current.impl));
            }
            functionTranslator(c, prefix, name, only_stub_virtual, vars,
                callbacks, current.hdr, current.impl);
            descend = false;
            break;
        case CXCursor_CXXAccessSpecifier:
            access_spec = CppAccessSpecifier(c.access.accessSpecifier);
            break;
        case CXCursor_CXXBaseSpecifier:
            inheritMethodTranslator(c, prefix, name, only_stub_virtual, vars,
                callbacks, current.get);
            descend = false;
            break;
        default:
            break;
        }

        return descend;
    }

private:
    CppClassName name;
    StubPrefix prefix;
    OnlyStubVirtual only_stub_virtual;

    //TODO chhange to RefCounted
    NullableRef!VariableContainer vars;
    NullableRef!CallbackContainer callbacks;

    CppAccessSpecifier access_spec;
}

private:

/** Traverse all inherited classes and call method translator on them.
 *
 * Thanks to how method translatorn is implemented it is recursive.
 * But this function, inheritMethodTranslator, is not. It traverses the leafs
 * and nothhing more.
 */
void inheritMethodTranslator(ref Cursor cursor, const StubPrefix prefix,
    const CppClassName name, const OnlyStubVirtual only_virt,
    ref VariableContainer vars, ref CallbackContainer callbacks, ref CppHdrImpl hdr_impl) {
    //TODO ugly hack. dunno what it should be so for now forcing to public.
    Nullable!CppAccessSpecifier access_spec;
    access_spec = CppAccessSpecifier(CX_CXXAccessSpecifier.CX_CXXPublic);

    logNode(cursor, 0);
    foreach (parent, child; cursor.all) {
        logNode(parent, 0);
        logNode(child, 0);

        auto p = parent.definition;

        switch (parent.kind) with (CXCursorKind) {
        case CXCursor_TypeRef:
            logNode(p, 1);
            MethodContext(prefix, name, access_spec, only_virt).translate(p,
                vars, callbacks, hdr_impl);
            break;
        default:
        }
    }
}
