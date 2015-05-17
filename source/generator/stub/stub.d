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

private:

import clang.c.index;
import clang.Cursor;

import dsrcgen.cpp;

import translator.Type;

import generator.stub.types;

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
        break;
    case CX_CXXProtected:
        node = hdr.protected_;
        break;
    case CX_CXXPrivate:
        node = hdr.private_;
        break;
    }

    return node;
}

CppHdrImpl namespaceTranslator(CppClassStructNsName nest, ref CppHdrImpl hdr_impl) {
    CppModule doHeader(ref CppModule hdr) {
        auto r = hdr.namespace(cast(string) nest);
        r.suppressIndent(1);
        hdr.sep(2);
        return r;
    }

    CppModule doImpl(ref CppModule impl) {
        auto r = impl.namespace(cast(string) nest);
        r.suppressIndent(1);
        impl.sep(2);
        return r;
    }

    return CppHdrImpl(doHeader(hdr_impl.hdr), doImpl(hdr_impl.impl));
}
