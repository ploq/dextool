/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 1, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */

module clang.TranslationUnit;

import std.string;
import std.typecons;

//import mambo.core.io;

import clang.c.index;
import clang.Cursor;
import clang.Diagnostic;
import clang.File;
import clang.Index;
import clang.SourceLocation;
import clang.Token;
import clang.UnsavedFile;
import clang.Util;
import clang.Visitor;

struct TranslationUnit {
    mixin CX;

    static RefCounted!TranslationUnit parse(Index index, string sourceFilename,
                                            string[] commandLineArgs,
                                            UnsavedFile[] unsavedFiles = null,
                                            uint options =
                                            CXTranslationUnit_Flags.CXTranslationUnit_None)
    {
        auto r = RefCounted!TranslationUnit();
        r = TranslationUnit(clang_parseTranslationUnit(index.cx,
            sourceFilename.toStringz, strToCArray(commandLineArgs), cast(int) commandLineArgs.length,
            toCArray!(CXUnsavedFile)(unsavedFiles), cast(uint) unsavedFiles.length, options));
        return r;
    }

    private this(CXTranslationUnit cx) {
        this.cx = cx;
    }

    @property DiagnosticVisitor diagnostics() {
        return DiagnosticVisitor(cx);
    }

    @property DeclarationVisitor declarations() {
        return DeclarationVisitor(clang_getTranslationUnitCursor(cx));
    }

    Nullable!File file(string filename) @trusted {
        Nullable!File r;

        auto f = clang_getFile(cx, filename.toStringz);
        if (f !is null) {
            r = File(f);
        }

        return r;
    }

    @property Cursor cursor() {
        auto r = clang_getTranslationUnitCursor(cx);
        return Cursor(r);
    }
}

/// Returns: the translation unit that a cursor originated from.
package TranslationUnit translationUnitFromCursor(CXCursor cx) @trusted {
    auto r = clang_Cursor_getTranslationUnit(cx);
    return TranslationUnit(r);
}

struct DiagnosticVisitor {
    private CXTranslationUnit translatoinUnit;

    this(CXTranslationUnit translatoinUnit) {
        this.translatoinUnit = translatoinUnit;
    }

    size_t length() {
        return clang_getNumDiagnostics(translatoinUnit);
    }

    int opApply(int delegate(ref Diagnostic) dg) {
        int result;

        foreach (i; 0 .. length) {
            auto diag = clang_getDiagnostic(translatoinUnit, cast(uint) i);
            auto dDiag = Diagnostic(diag);
            result = dg(dDiag);

            if (result)
                break;
        }

        return result;
    }
}
