/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module clang.Token;

import std.conv;
import std.string;
import std.experimental.logger;

import clang.c.index;
import clang.SourceLocation;
import clang.TranslationUnit;
import clang.Type;
import clang.Util;
import clang.Visitor;

import tested;

version (unittest) {
    shared static this() {
        import std.exception;
        enforce(runUnitTests!(clang.Token)(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

struct Token
{
    //TODO change to a reference or something. I think this is very memory inefficient.
    private TranslationUnit tu;
    mixin CX;

    this (ref TranslationUnit tu)
    {
        this.tu = tu;
    }

    @property CXTokenKind kind ()
    {
        return clang_getTokenKind(cx);
    }

    @property string spelling ()
    {
        return toD(clang_getTokenSpelling(tu, cx));
    }

    @property SourceLocation location ()
    {
        auto r = clang_getTokenLocation(tu, cx);
        return SourceLocation(r);
    }

    // left to implement
    //CXSourceRange clang_getTokenExtent(CXTranslationUnit, CXToken);
    //void clang_tokenize(CXTranslationUnit TU, CXSourceRange Range,
    //                                   CXToken **Tokens, uint* NumTokens);
    //void clang_annotateTokens(CXTranslationUnit TU,
    //                                         CXToken* Tokens, uint NumTokens,
    //                                         CXCursor* Cursors);

}

@name("Test of Token")
unittest {
    import clang.Cursor;
    import clang.Index;
    import clang.TranslationUnit;

    string expect = """ """;

    globalLogLevel(LogLevel.trace);
    auto index = Index(false, false);
    auto translation_unit = TranslationUnit.parse(index, "test_files/class_interface.hpp", ["-xc++"]);

    struct StupidVisitor {
        void incr() {}
        void decr() {}
        bool apply(Cursor c) {
            return true;
        }
    }

    StupidVisitor ctx;
    auto cursor = translation_unit.cursor;
    //visit_ast!StupidVisitor(cursor, ctx);

    //auto rval = ctx.render;
    //assert(rval == expect, rval);

    // is thhis needed?
    //translation_unit.dispose;
    //index.dispose;
}
