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
import clang.SourceRange;
import clang.Type;
import clang.TranslationUnit;
import clang.Util;
import clang.Visitor;

/** The Cursor class represents a reference to an element within the AST. It
 *  acts as a kind of iterator.
 */
struct Cursor {
    mixin CX;

    /// Retrieve the NULL cursor, which represents no entity.
    @property static Cursor empty() {
        auto r = clang_getNullCursor();
        return Cursor(r);
    }

    /// Return: the spelling of the entity pointed at by the cursor.
    @property string spelling() {
        return toD(clang_getCursorSpelling(cx));
    }

    /** Return the display name for the entity referenced by this cursor.
     *
     *  The display name contains extra information that helps identify the
     *  cursor, such as the parameters of a function or template or the
     *  arguments of a class template specialization.
     */
    @property string displayName() {
        return toD(clang_getCursorDisplayName(cx));
    }

    /// Return: the kind of this cursor.
    @property CXCursorKind kind() @trusted {
        return clang_getCursorKind(cx);
    }

    /** Retrieve the physical location of the source constructor referenced by
     * the given cursor.
     *
     * The location of a declaration is typically the location of the name of
     * that declaration, where the name of that declaration would occur if it
     * is unnamed, or some keyword that introduces that particular declaration.
     * The location of a reference is where that reference occurs within the
     * source code.
     */
    @property SourceLocation location() {
        return SourceLocation(clang_getCursorLocation(cx));
    }

    /// Return: Retrieve the Type (if any) of the entity pointed at by the cursor.
    @property Type type() @trusted {
        auto r = clang_getCursorType(cx);
        return Type(r);
    }

    /** Return the underlying type of a typedef declaration.
     * Returns: a Type for the typedef this cursor is a declaration for.
     *
     * If the current cursor is not a typedef, this raises.
     */
    @property Type typedefUnderlyingType() @trusted {
        auto r = clang_getTypedefDeclUnderlyingType(cx);
        return Type(r);
    }

    /** If the cursor is a reference to a declaration or a declaration of
     *  some entity, return a cursor that points to the definition of that
     *  entity.
     */
    @property Cursor definition() {
        auto r = clang_getCursorDefinition(cx);
        return Cursor(r);
    }

    /** Determine the semantic parent of the given cursor.
     *
     * The semantic parent of a cursor is the cursor that semantically contains
     * the given cursor. For many declarations, the lexical and semantic
     * parents are equivalent (the lexical parent is returned by
     * clang_getCursorLexicalParent()). They diverge when declarations or
     * definitions are provided out-of-line. For example:
     *
     * ---
     * class C {
     *  void f();
     * }
     *
     * void C::f() { }
     * ---
     *
     * In the out-of-line definition of C::f, the semantic parent is the the
     * class C, of which this function is a member. The lexical parent is the
     * place where the declaration actually occurs in the source code; in this
     * case, the definition occurs in the translation unit. In general, the
     * lexical parent for a given entity can change without affecting the
     * semantics of the program, and the lexical parent of different
     * declarations of the same entity may be different. Changing the semantic
     * parent of a declaration, on the other hand, can have a major impact on
     * semantics, and redeclarations of a particular entity should all have the
     * same semantic context.
     *
     * In the example above, both declarations of C::f have C as their semantic
     * context, while the lexical context of the first C::f is C and the
     * lexical context of the second C::f is the translation unit.
     *
     * For global declarations, the semantic parent is the translation unit.
     */
    @property Cursor semanticParent() {
        auto r = clang_getCursorSemanticParent(cx);
        return Cursor(r);
    }

    /** Determine the lexical parent of the given cursor.
     *
     * The lexical parent of a cursor is the cursor in which the given cursor
     * was actually written. For many declarations, the lexical and semantic
     * parents are equivalent (the semantic parent is returned by
     * clang_getCursorSemanticParent()). They diverge when declarations or
     * definitions are provided out-of-line. For example:
     *
     * ---
     * class C {
     *  void f();
     * }
     *
     * void C::f() { }
     * ---
     *
     * In the out-of-line definition of C::f, the semantic parent is the the
     * class C, of which this function is a member. The lexical parent is the
     * place where the declaration actually occurs in the source code; in this
     * case, the definition occurs in the translation unit. In general, the
     * lexical parent for a given entity can change without affecting the
     * semantics of the program, and the lexical parent of different
     * declarations of the same entity may be different. Changing the semantic
     * parent of a declaration, on the other hand, can have a major impact on
     * semantics, and redeclarations of a particular entity should all have the
     * same semantic context.
     *
     * In the example above, both declarations of C::f have C as their semantic
     * context, while the lexical context of the first C::f is C and the
     * lexical context of the second \c C::f is the translation unit.
     *
     * For declarations written in the global scope, the lexical parent is
     * the translation unit.
     */
    @property Cursor lexicalParent() {
        auto r = clang_getCursorLexicalParent(cx);
        return Cursor(r);
    }

    /** For a cursor that is a reference, retrieve a cursor representing the
     * entity that it references.
     *
     * Reference cursors refer to other entities in the AST. For example, an
     * Objective-C superclass reference cursor refers to an Objective-C class.
     * This function produces the cursor for the Objective-C class from the
     * cursor for the superclass reference. If the input cursor is a
     * declaration or definition, it returns that declaration or definition
     * unchanged.  Otherwise, returns the NULL cursor.
     */
    @property Cursor referenced() {
        auto r = clang_getCursorReferenced(cx);
        return Cursor(r);
    }

    @property DeclarationVisitor declarations() {
        return DeclarationVisitor(cx);
    }

    /** Retrieve the physical extent of the source construct referenced by the
     * given cursor.
     *
     * The extent of a cursor starts with the file/line/column pointing at the
     * first character within the source construct that the cursor refers to
     * and ends with the last character withinin that source construct. For a
     * declaration, the extent covers the declaration itself. For a reference,
     * the extent covers the location of the reference (e.g., where the
     * referenced entity was actually used).
     */
    @property SourceRange extent() @trusted {
        auto r = clang_getCursorExtent(cx);
        return SourceRange(r);
    }

    /** Retrieve the canonical cursor corresponding to the given cursor.
     *
     * In the C family of languages, many kinds of entities can be declared
     * several times within a single translation unit. For example, a structure
     * type can be forward-declared (possibly multiple times) and later
     * defined:
     *
     * ---
     * struct X;
     * struct X;
     * struct X {
     *   int member;
     * }
     * ---
     *
     * The declarations and the definition of X are represented by three
     * different cursors, all of which are declarations of the same underlying
     * entity. One of these cursor is considered the "canonical" cursor, which
     * is effectively the representative for the underlying entity. One can
     * determine if two cursors are declarations of the same underlying entity
     * by comparing their canonical cursors.
     *
     * Return: The canonical cursor for the entity referred to by the given cursor.
     */
    @property Cursor canonical() @trusted {
        auto r = clang_getCanonicalCursor(cx);
        return Cursor(r);
    }

    /// Determine the "language" of the entity referred to by a given cursor.
    @property CXLanguageKind language() {
        return clang_getCursorLanguage(cx);
    }

    /// Returns: the translation unit that a cursor originated from.
    @property TranslationUnit translationUnit() @trusted {
        return translationUnitFromCursor(cx);
    }

    @property ObjcCursor objc() {
        return ObjcCursor(this);
    }

    @property FunctionCursor func() {
        return FunctionCursor(this);
    }

    @property EnumCursor enum_() @trusted {
        return EnumCursor(this);
    }

    @property AccessCursor access() {
        return AccessCursor(this);
    }

    @property Visitor all() {
        return Visitor(this);
    }

    /// Determine whether two cursors are equivalent.
    equals_t opEquals(const ref Cursor cursor) const {
        return clang_equalCursors(cast(CXCursor) cursor.cx, cast(CXCursor) cx) != 0;
    }

    hash_t toHash() const {
        return clang_hashCursor(cast(CXCursor) cx);
    }

    /// Determine whether the given cursor kind represents a declaration.
    @property bool isDeclaration() {
        return clang_isDeclaration(cx.kind) != 0;
    }

    /// Determine whether the given cursor kind represents an invalid cursor.
    @property bool isValid() {
        return !clang_isInvalid(cx.kind);
    }

    /// Return: if cursor is null/empty.
    @property bool isEmpty() {
        return clang_Cursor_isNull(cx) != 0;
    }

    /** Returns true if the declaration pointed at by the cursor is also a
     * definition of that entity.
     */
    bool isDefinition() const {
        return clang_isCursorDefinition(cast(CXCursor) cx) != 0;
    }

    /// Determine whether the given cursor kind represents a translation unit.
    @property bool isTranslationUnit() {
        return clang_isTranslationUnit(kind) == 0;
    }

    /// Returns: if the base class specified by the cursor with kind CX_CXXBaseSpecifier is virtual.
    @property bool isVirtualBase() {
        return clang_isVirtualBase(cx) == 1;
    }
}

struct ObjcCursor {
    Cursor cursor;
    alias cursor this;

    @property ObjCInstanceMethodVisitor instanceMethods() {
        return ObjCInstanceMethodVisitor(cursor);
    }

    @property ObjCClassMethodVisitor classMethods() {
        return ObjCClassMethodVisitor(cursor);
    }

    @property ObjCPropertyVisitor properties() {
        return ObjCPropertyVisitor(cursor);
    }

    @property Cursor superClass() {
        foreach (cursor, parent; TypedVisitor!(CXCursorKind.CXCursor_ObjCSuperClassRef)(cursor))
            return cursor;

        return Cursor.empty;
    }

    @property ObjCProtocolVisitor protocols() {
        return ObjCProtocolVisitor(cursor);
    }

    @property Cursor category() {
        assert(cursor.kind == CXCursorKind.CXCursor_ObjCCategoryDecl);

        foreach (c, _; TypedVisitor!(CXCursorKind.CXCursor_ObjCClassRef)(cursor))
            return c;

        assert(0, "This cursor does not have a class reference.");
    }
}

struct FunctionCursor {
    Cursor cursor;
    alias cursor this;

    /// Return: Retrieve the Type of the result for this Cursor.
    @property Type resultType() {
        auto r = clang_getCursorResultType(cx);
        return Type(r);
    }

    @property ParamVisitor parameters() {
        return ParamVisitor(cx);
    }

    @property bool isVariadic() {
        return type.func.isVariadic;
    }

    /** Returns: True if the cursor refers to a C++ member function or member
     * function template that is declared 'static'.
     */
    @property bool isStatic() @trusted {
        return clang_CXXMethod_isStatic(cx) != 0;
    }
}

struct AccessCursor {
    Cursor cursor;
    alias cursor this;

    /** Returns the access control level for the C++ base specifier represented
     * by a cursor with kind CXCursor_CXXBaseSpecifier or
     * CXCursor_AccessSpecifier.
     */
    @property auto accessSpecifier() {
        return clang_getCXXAccessSpecifier(cx);
    }
}

struct ParamCursor {
    Cursor cursor;
    alias cursor this;
}

struct EnumCursor {
    Cursor cursor;
    alias cursor this;

    @property string value() @safe {
        return to!string(signedValue);
    }

    /** Retrieve the integer type of an enum declaration.
     *
     * If the cursor does not reference an enum declaration, an invalid type is
     * returned.
     */
    @property Type type() @trusted {
        auto r = clang_getEnumDeclIntegerType(cx);
        return Type(r);
    }

    /** Retrieve the integer value of an enum constant declaration as a signed
     * long.
     *
     * If the cursor does not reference an enum constant declaration, LLONG_MIN
     * is returned.  Since this is also potentially a valid constant value, the
     * kind of the cursor must be verified before calling this function.
     */
    @property long signedValue() @trusted {
        return clang_getEnumConstantDeclValue(cx);
    }

    /** Retrieve the integer value of an enum constant declaration as an
     * unsigned long.
     *
     * If the cursor does not reference an enum constant declaration,
     * ULLONG_MAX is returned.  Since this is also potentially a valid constant
     * value, the kind of the cursor must be verified before calling this
     * function.
     */
    @property ulong unsignedValue() @trusted {
        return clang_getEnumConstantDeclUnsignedValue(cx);
    }

    /// Return: if the underlying type is an enum.
    @property bool isUnderlyingTypeEnum() @safe {
        auto t = typedefUnderlyingType.declaration.enum_;
        return t.kind == CXTypeKind.CXType_Enum;
    }

    /// Return: if the type of the enum is signed.
    @property bool isSigned() @trusted {
        Type t;

        if (isUnderlyingTypeEnum) {
            t = typedefUnderlyingType.declaration.enum_.type;
        }
        else {
            t = Type(clang_getCursorType(cx));
        }

        with(CXTypeKind) {
            switch (t.kind) {
                case CXType_Char_U:
                case CXType_UChar:
                case CXType_Char16:
                case CXType_Char32:
                case CXType_UShort:
                case CXType_UInt:
                case CXType_ULong:
                case CXType_ULongLong:
                case CXType_UInt128:
                    return false;
                default:
                    return true;
            }
        }
    }
}
