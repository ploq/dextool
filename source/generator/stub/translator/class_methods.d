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
module generator.stub.translator.class_methods;

private:

import std.typecons : TypedefType, NullableRef, Nullable;

import clang.c.index;
import clang.Cursor;

import generator.analyzer : visitAst, IdStack, logNode, VisitNodeModule;
import generator.stub.types;
import generator.stub.containers : CallbackContainer, VariableContainer;
import generator.stub.stub : consumeAccessSpecificer;
import generator.stub.translator.functionx;

/** Translate class methods to stub implementation.
 */
public struct MethodTranslateContext {
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
        visitAst!MethodTranslateContext(cursor, this);
    }

    bool apply(Cursor c) {
        bool descend = true;
        logNode(c, depth);

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

    logNode(cursor, 0);
    foreach (parent, child; cursor.all) {
        logNode(parent, 0);
        logNode(child, 0);

        auto p = parent.definition;

        switch (parent.kind) with (CXCursorKind) {
        case CXCursor_TypeRef:
            logNode(p, 1);
            MethodTranslateContext(name, access_spec).translate(p, vars, callbacks,
                hdr_impl);
            break;
        default:
        }
    }
}
