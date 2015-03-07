/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module clang.SourceRange;

import std.conv;
import std.string;
import std.experimental.logger;

import clang.c.index;
import clang.SourceLocation;
import clang.Util;

import tested;

version (unittest) {
    shared static this() {
        import std.exception;
        enforce(runUnitTests!(clang.SourceRange)(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

struct SourceRange
{
    mixin CX;

    /// Retrieve a NULL (invalid) source range.
    static SourceRange empty ()
    {
        auto r = clang_getNullRange();
        return SourceRange(r);
    }

    /// Retrieve a source location representing the first character within a source range.
    @property SourceLocation start ()
    {
        auto r = clang_getRangeStart(cx);
        return SourceLocation(r);
    }

    /// Retrieve a source location representing the last character within a source range.
    @property SourceLocation end ()
    {
        auto r = clang_getRangeEnd(cx);
        return SourceLocation(r);
    }

    bool isNull ()
    {
        return clang_Range_isNull(cx) != 0;
    }

    equals_t opEquals (const ref SourceRange range2) const
    {
        return clang_equalRanges(cast(CXSourceRange) cx, cast(CXSourceRange) range2) != 0;
    }
}

/// Retrieve a source range given the beginning and ending source locations.
SourceRange range (ref SourceLocation begin, SourceLocation end)
{
    auto r = clang_getRange(begin.cx, end.cx);
    return SourceRange(r);
}

@name("Test of null range")
unittest {
    auto r = SourceRange.empty();

    assert(r.isNull == true);
}
