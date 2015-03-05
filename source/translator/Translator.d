/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 6, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module translator.Translator;

import std.file;
import std.conv;

import clang.c.index;
import clang.Cursor;
import clang.File;
import clang.TranslationUnit;
import clang.Type;
import clang.Util;

//import dstep.translator.Declaration;
//import dstep.translator.Enum;
//import dstep.translator.IncludeHandler;
//import dstep.translator.objc.Category;
//import dstep.translator.objc.ObjcInterface;
//import dstep.translator.Output;
//import dstep.translator.Record;
import translator.Type;

private static string[Cursor] anonymousNames;

string getAnonymousName (Cursor cursor)
{
    if (auto name = cursor in anonymousNames)
        return *name;

    return "";
}

string generateAnonymousName (Cursor cursor)
{
    auto name = getAnonymousName(cursor);

    if (name.length == 0)
    {
        name = "_Anonymous_" ~ to!string(anonymousNames.length);
        anonymousNames[cursor] = name;
    }

    return name;
}

string getInclude (Type type)
    in
{
    assert(type.isValid);
}
body
{
    return type.declaration.location.spelling.file.name;
}
