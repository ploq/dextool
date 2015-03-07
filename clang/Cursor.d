/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 1, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module clang.Cursor;

import std.conv;

import clang.c.index;
import clang.SourceLocation;
import clang.Type;
import clang.Util;
import clang.Visitor;

struct Cursor
{
    mixin CX;

    @property static Cursor empty () {
        auto r = clang_getNullCursor();
        return Cursor(r);
    }

    @property string spelling ()
    {
        return toD(clang_getCursorSpelling(cx));
    }

    @property string displayName ()
    {
        return toD(clang_getCursorDisplayName(cx));
    }

    @property CXCursorKind kind ()
    {
        return clang_getCursorKind(cx);
    }

    @property SourceLocation location ()
    {
        return SourceLocation(clang_getCursorLocation(cx));
    }

    @property Type type ()
    {
        auto r = clang_getCursorType(cx);
        return Type(r);
    }

    @property Type typedefUnderlyingType ()
    {
        auto r = clang_getTypedefDeclUnderlyingType(cx);
        return Type(r);
    }

    @property Cursor definition ()
    {
        auto r = clang_getCursorDefinition(cx);
        return Cursor(r);
    }

    /// Returns: the semantic parent for this cursor.
    @property Cursor semanticParent()
    {
        auto r = clang_getCursorSemanticParent(cx);
        return Cursor(r);
    }

    /// Returns: the lexical parent for this cursor.
    @property Cursor lexicalParent()
    {
        auto r = clang_getCursorLexicalParent(cx);
        return Cursor(r);
    }

    /** For a cursor that is a reference, returns a cursor representing the
     * entity that it references.
     */
    @property Cursor referenced()
    {
        auto r = clang_getCursorReferenced(cx);
        return Cursor(r);
    }

    @property DeclarationVisitor declarations ()
    {
        return DeclarationVisitor(cx);
    }

    @property ObjcCursor objc ()
    {
        return ObjcCursor(this);
    }

    @property FunctionCursor func ()
    {
        return FunctionCursor(this);
    }

    @property EnumCursor enum_ ()
    {
        return EnumCursor(this);
    }

    @property AccessCursor access()
    {
        return AccessCursor(this);
    }

    @property Visitor all ()
    {
        return Visitor(this);
    }

    @property CXLanguageKind language ()
    {
        return clang_getCursorLanguage(cx);
    }

    equals_t opEquals (const ref Cursor cursor) const
    {
        return clang_equalCursors(cast(CXCursor) cursor.cx, cast(CXCursor) cx) != 0;
    }

    hash_t toHash () const
    {
        return clang_hashCursor(cast(CXCursor) cx);
    }

    @property bool isDeclaration ()
    {
        return clang_isDeclaration(cx.kind) != 0;
    }

    @property bool isValid ()
    {
        return !clang_isInvalid(cx.kind);
    }

    @property bool isEmpty ()
    {
        return clang_Cursor_isNull(cx) != 0;
    }

    bool isDefinition () const
    {
        return clang_isCursorDefinition(cast(CXCursor) cx) != 0;
    }

    @property bool isTranslationUnit()
    {
        return clang_isTranslationUnit(kind) == 0;
    }

    /// Returns: if the base class specified by the cursor with kind CX_CXXBaseSpecifier is virtual.
    @property bool isVirtualBase() {
        return clang_isVirtualBase(cx) == 1;
    }
}

struct ObjcCursor
{
    Cursor cursor;
    alias cursor this;

    @property ObjCInstanceMethodVisitor instanceMethods ()
    {
        return ObjCInstanceMethodVisitor(cursor);
    }

    @property ObjCClassMethodVisitor classMethods ()
    {
        return ObjCClassMethodVisitor(cursor);
    }

    @property ObjCPropertyVisitor properties ()
    {
        return ObjCPropertyVisitor(cursor);
    }

    @property Cursor superClass ()
    {
        foreach (cursor, parent ; TypedVisitor!(CXCursorKind.CXCursor_ObjCSuperClassRef)(cursor))
            return cursor;

        return Cursor.empty;
    }

    @property ObjCProtocolVisitor protocols ()
    {
        return ObjCProtocolVisitor(cursor);
    }

    @property Cursor category ()
    {
        assert(cursor.kind == CXCursorKind.CXCursor_ObjCCategoryDecl);

        foreach (c, _ ; TypedVisitor!(CXCursorKind.CXCursor_ObjCClassRef)(cursor))
            return c;

        assert(0, "This cursor does not have a class reference.");
    }
}

struct FunctionCursor
{
    Cursor cursor;
    alias cursor this;

    @property Type resultType ()
    {
        auto r = clang_getCursorResultType(cx);
        return Type(r);
    }

    @property bool isVariadic ()
    {
        return type.func.isVariadic;
    }

    @property ParamVisitor parameters ()
    {
        return ParamVisitor(cx);
    }
}

struct AccessCursor
{
    Cursor cursor;
    alias cursor this;

    @property auto accessSpecifier() {
        return clang_getCXXAccessSpecifier(cx);
    }
}

struct ParamCursor
{
    Cursor cursor;
    alias cursor this;
}

struct EnumCursor
{
    Cursor cursor;
    alias cursor this;

    @property string value ()
    {
        return to!string(signedValue);
    }

    @property long signedValue ()
    {
        return clang_getEnumConstantDeclValue(cx);
    }

    @property ulong unsignedValue ()
    {
        return clang_getEnumConstantDeclUnsignedValue(cx);
    }
}
