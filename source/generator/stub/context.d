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
import generator.stub.translator;

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
