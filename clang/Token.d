/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module clang.Token;

import std.conv;
import std.string;
import std.typecons;
import std.experimental.logger;

import clang.c.index;
import clang.Cursor;
import clang.SourceLocation;
import clang.SourceRange;
import clang.TranslationUnit;
import clang.Util;
import clang.Visitor;

import tested;

version (unittest) {
    shared static this() {
        import std.exception;

        enforce(runUnitTests!(clang.Token)(new ConsoleTestResultWriter),
            "Unit tests failed.");
    }
}

string toString(ref Token tok) {
    import std.conv;

    if (tok.isValid) {
        return format("%s(%s) [spelling='%s']", text(typeid(tok)), text(tok.cx),
            tok.spelling);
    }

    return text(tok);
}

auto toString(ref TokenGroup toks) {
    string s;

    foreach (t; toks) {
        if (t.isValid) {
            s ~= t.spelling ~ " ";
        }
    }

    return s.strip;
}

auto toString(RefCounted!TokenGroup toks) {
    return toks.refCountedPayload.toString;
}

/** Represents a single token from the preprocessor.
 *
 *  Tokens are effectively segments of source code. Source code is first parsed
 *  into tokens before being converted into the AST and Cursors.
 *
 *  Tokens are obtained from parsed TranslationUnit instances. You currently
 *  can't create tokens manually.
 */
struct Token {
    private alias CType = CXToken;
    CType cx;
    alias cx this;

    private RefCounted!TokenGroup group;

    this(RefCounted!TokenGroup group, ref CXToken token) {
        group = group;
        cx = token;
    }

    /// Obtain the TokenKind of the current token.
    @property CXTokenKind kind() {
        return clang_getTokenKind(cx);
    }

    /** The spelling of this token.
     *
     *  This is the textual representation of the token in source.
     */
    @property string spelling() {
        return toD(clang_getTokenSpelling(group.tu, cx));
    }

    /// The SourceLocation this Token occurs at.
    @property SourceLocation location() {
        auto r = clang_getTokenLocation(group.tu, cx);
        return SourceLocation(r);
    }

    /// The SourceRange this Token occupies.
    @property SourceRange extent() {
        auto r = clang_getTokenExtent(group.tu, cx);
        return SourceRange(r);
    }

    /// The Cursor this Token corresponds to.
    @property Cursor cursor() {
        Cursor c = Cursor.empty;

        clang_annotateTokens(group.tu, &cx, 1, &c.cx);

        return c;
    }

    @property bool isValid() {
        return cx !is CType.init;
    }
}

/** Tokenize the source code described by the given range into raw
 * lexical tokens.
 *
 * Params:
 *  TU = the translation unit whose text is being tokenized.
 *
 *  Range = the source range in which text should be tokenized. All of the
 * tokens produced by tokenization will fall within this source range,
 *
 *  Tokens = this pointer will be set to point to the array of tokens
 * that occur within the given source range. The returned pointer must be
 * freed with clang_disposeTokens() before the translation unit is destroyed.
 *
 *  NumTokens = will be set to the number of tokens in the \c* Tokens
 * array.
 */
RefCounted!TokenGroup tokenize(RefCounted!TranslationUnit tu, SourceRange range) {
    TokenGroup.CXTokenArray tokens;
    auto tg = RefCounted!TokenGroup(tu);

    clang_tokenize(tu, range, &tokens.tokens, &tokens.length);
    tg.cxtokens = tokens;

    foreach (i; 0 .. tokens.length) {
        tg.tokens ~= Token(tg, tokens.tokens[i]);
    }

    return tg;
}

private:



/** Helper class to facilitate token management.
 * Tokens are allocated from libclang in chunks. They must be disposed of as a
 * collective group.
 *
 * One purpose of this class is for instances to represent groups of allocated
 * tokens. Each token in a group contains a reference back to an instance of
 * this class. When all tokens from a group are garbage collected, it allows
 * this class to be garbage collected. When this class is garbage collected,
 * it calls the libclang destructor which invalidates all tokens in the group.
 *
 * You should not instantiate this class outside of this module.
 */
struct TokenGroup {
    alias Delegate = int delegate(ref Token);

    private RefCounted!TranslationUnit tu;
    private CXTokenArray cxtokens;
    private Token[] tokens;

    struct CXTokenArray {
        CXToken* tokens;
        uint length;
    }

    this(RefCounted!TranslationUnit tu) {
        tu = tu;
    }

    ~this() {
        if (cxtokens.length > 0) {
            clang_disposeTokens(tu.cx, cxtokens.tokens, cxtokens.length);
            cxtokens.length = 0;
            tokens.length = 0;
        }
    }

    auto opIndex(T)(T idx) {
        return tokens[idx];
    }

    auto opIndex(T...)(T ks) {
        Token[] rval;

        foreach (k; ks) {
            rval ~= tokens[k];
        }

        return rval;
    }

    auto opDollar(int dim)() {
        return length;
    }

    @property auto length() {
        return tokens.length;
    }

    auto opApply(Delegate dg) {
        foreach (tok; tokens) {
            if (auto result = dg(tok))
                return result;
        }

        return 0;
    }
}

@name("Test of tokenizing a range") unittest {
    import clang.Index;
    import std.conv;

    globalLogLevel(LogLevel.info);
    auto index = Index(false, false);
    auto filename = "test_files/class_funcs.hpp";
    auto tu = TranslationUnit.parse(index, filename, ["-xc++"]);
    auto file = tu.file(filename);

    auto loc1 = SourceLocation.fromOffset(tu, file, 0);
    auto loc2 = SourceLocation.fromPosition(tu, file, 13, 15);
    assert(loc1.spelling.file.name == filename, text(loc1.spelling));
    assert(loc2.spelling.file.name == filename, text(loc2.spelling));

    auto range1 = range(loc1, loc2);
    auto token_group = tokenize(tu, range1);

    assert(token_group.length > 0, "Expected length > 0 but it is " ~ to!string(
        token_group.length));
    foreach (token; token_group) {
        trace(token.toString);
    }

    assert(token_group[$ - 1].spelling == "MadeUp", token_group[$ - 1].toString);
}

@name("Test of Token") unittest {
    import clang.Index;

    string expect = """ """;

    globalLogLevel(LogLevel.trace);
    auto index = Index(false, false);
    auto translation_unit = TranslationUnit.parse(index,
        "test_files/class_interface.hpp", ["-xc++"]);

    struct StupidVisitor {
        void incr() {
        }

        void decr() {
        }

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