/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 29, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module clang.SourceLocation;

import clang.c.index;
import clang.File;
import clang.TranslationUnit;
import clang.Util;

struct SourceLocation
{
    mixin CX;

    struct Location
    {
        File file;
        uint line;
        uint column;
        uint offset;
    }

     /// Retrieve a NULL (invalid) source location.
    static SourceLocation empty ()
    {
        auto r = clang_getNullLocation();
        return SourceLocation(r);
    }

    /** Retrieves the source location associated with a given file/line/column
     * in a particular translation unit.
     */
    ///TODO consider moving to TranslationUnit instead
    SourceLocation fromPosition(ref TranslationUnit tu, Location location)
    {
        auto r = clang_getLocation(tu, location.file, location.column, location.offset);
        return SourceLocation(r);
    }

    /** Retrieves the source location associated with a given character offset
     * in a particular translation unit.
     */
    ///TODO consider moving to TranslationUnit instead
    SourceLocation fromOffset(ref TranslationUnit tu, Location location)
    {
        auto r = clang_getLocation(tu, location.file, location.column, location.offset);
        return SourceLocation(r);
    }

    /** Retrieve the file, line, column, and offset represented by
     * the given source location.
     *
     * If the location refers into a macro expansion, retrieves the
     * location of the macro expansion.
     *
     * Params:
     *  location = the location within a source file that will be decomposed
     * into its parts.
     *
     *  file = [out] if non-NULL, will be set to the file to which the given
     * source location points.
     *
     *  line = [out] if non-NULL, will be set to the line to which the given
     * source location points.
     *
     *  column = [out] if non-NULL, will be set to the column to which the given
     * source location points.
     *
     *  offset = [out] if non-NULL, will be set to the offset into the
     * buffer to which the given source location points.
     */
    @property Location expansion ()
    {
        Location data;

        clang_getExpansionLocation(cx, &data.file.cx, &data.line, &data.column, &data.offset);

        return data;
    }

    /** Retrieve the file, line, column, and offset represented by
     * the given source location, as specified in a # line directive.
     *
     * Example: given the following source code in a file somefile.c
     * ---
     * #123 "dummy.c" 1
     *
     * static int func()
     * {
     *     return 0;
     * }
     * ---
     * the location information returned by this function would be
     * ---
     * File: dummy.c Line: 124 Column: 12
     * ---
     * whereas clang_getExpansionLocation would have returned
     * ---
     * File: somefile.c Line: 3 Column: 12
     * ---
     * Params:
     *  location = the location within a source file that will be decomposed
     * into its parts.
     *
     *  filename = [out] if non-NULL, will be set to the filename of the
     * source location. Note that filenames returned will be for "virtual" files,
     * which don't necessarily exist on the machine running clang - e.g. when
     * parsing preprocessed output obtained from a different environment. If
     * a non-NULL value is passed in, remember to dispose of the returned value
     * using \c clang_disposeString() once you've finished with it. For an invalid
     * source location, an empty string is returned.
     *
     *  line = [out] if non-NULL, will be set to the line number of the
     * source location. For an invalid source location, zero is returned.
     *
     *  column = [out] if non-NULL, will be set to the column number of the
     * source location. For an invalid source location, zero is returned.
     */
    void presumed (out string filename, out uint line, out uint column)
    {
        CXString cxstring;

        clang_getPresumedLocation(cx, &cxstring, &line, &column);
        filename = toD(cxstring);
    }

    /** Retrieve the file, line, column, and offset represented by
     * the given source location.
     *
     * If the location refers into a macro instantiation, return where the
     * location was originally spelled in the source file.
     *
     * Params:
     *  location = the location within a source file that will be decomposed
     * into its parts.
     *
     *  file = [out] if non-NULL, will be set to the file to which the given
     * source location points.
     *
     *  line = [out] if non-NULL, will be set to the line to which the given
     * source location points.
     *
     *  column = [out] if non-NULL, will be set to the column to which the given
     * source location points.
     *
     *  offset = [out] if non-NULL, will be set to the offset into the
     * buffer to which the given source location points.
     */
    @property Location spelling ()
    {
        Location data;

        clang_getSpellingLocation(cx, &data.file.cx, &data.line, &data.column, &data.offset);

        return data;
    }
}
