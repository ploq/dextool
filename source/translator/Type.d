/**
 * Copyright: Copyright (c) 2012 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 30, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */

module translator.Type;

import std.array;
import std.conv;
import std.string;
import std.experimental.logger;

import clang.c.index;
import clang.Cursor;
import clang.Token;
import clang.Type;

import translator.Translator;

struct TypeKind {
    string name;
    bool isConst;
    bool isRef;
    bool isPointer;
}

string toString(in TypeKind type) {
    return type.name;
}

/** Translate a cursors type to a struct representation.
 * Params:
 *   type = a clang cursor to the type node
 * Returns: Struct of metadata about the type.
 */
TypeKind translateType(Type type)
in {
    assert(type.isValid);
}
body {
    TypeKind result;

    auto tmp_c = type.declaration;
    auto tmp_t = tmp_c.typedefUnderlyingType;
    trace(format("%s %s c:%s t:%s", tmp_c.spelling, abilities(tmp_t),
        abilities(tmp_c), abilities(type)));

    with (CXTypeKind) {
        if (type.kind == CXType_BlockPointer || type.isFunctionPointerType)
            error("Implement missing translation of function pointer");
        //    result = translateFunctionPointerType(type);

        if (type.isWideCharType)
            result.name = "wchar";
        else {
            switch (type.kind) {
            case CXType_Pointer:
                result = translatePointer(type);
                break;
            case CXType_Typedef:
                result = translateTypedef(type);
                break;

            case CXType_Record:
            case CXType_Enum:
                // fix suffix and isConst
                result.name = type.spelling;
                if (result.name.length == 0)
                    result.name = getAnonymousName(type.declaration);
                break;

            case CXType_ConstantArray:
                result.name = translateConstantArray(type, false);
                break;
            case CXType_Unexposed:
                result.name = translateUnexposed(type, false);
                break;
            case CXType_LValueReference:
                result = translateReference(type);
                break;

            default:
                trace(format("%s|%s|%s|%s", type.kind, type.declaration,
                    type.isValid, type.typeKindSpelling));
                result.name = type.spelling;
            }
        }
    }

    return result;
}

/** Extract properties from a Cursor for a Type like const, pointer, reference.
 * Params:
 *  cursor = A cursor that have a type property.
 */
TypeKind toProperty(ref Cursor cursor) {
    TypeKind result;

    if (cursor.type.isConst) {
        result.isConst = true;
    }

    if (cursor.type.declaration.isReference) {
        result.isRef = true;
    }

    if (cursor.type.kind == CXTypeKind.CXType_Pointer) {
        result.isPointer = true;
    }

    return result;
}

/** Translate a cursor for a type to a TypeKind.
 *
 * Useful when a diagnostic error is detected. Then the translation must be
 * done on the tokens. At least for the undefined types. Otherwise they will be
 * assuemed to be int's.
 *
 * Assumtion made:
 * The cursor's spelling returns the token denoting "the variable name".
 * Everything up to "the variable name" is "the type".
 *
 * Params:
 *  cursor = Cursor to translate.
 */
TypeKind translateTypeCursor(ref Cursor cursor) {
    import std.algorithm : among;
    import clang.Token : toString;
    import clang.SourceRange : toString;

    trace(clang.SourceRange.toString(cursor.extent));

    enum State {
        Prefix,
        Suffix,
        Done
    }

    TypeKind r = cursor.toProperty();
    auto tokens = cursor.tokens();
    auto cursor_identifier = cursor.spelling; // name of the cursors identifier but NOT the type.
    trace(tokens.length, "|", tokens.toString, "|", cursor.type.spelling, "|", cursor_identifier);

    State st;
    foreach (t; tokens) {
        trace(clang.Token.toString(t), " ", text(st));

        final switch (st) {
        case State.Prefix:
            switch (t.kind) {
            case CXTokenKind.CXToken_Identifier:
                if (t.spelling == cursor_identifier) {
                    st = State.Done;
                }
                else {
                    r.name ~= (r.name.length == 0 ? "" : " ") ~ t.spelling;
                    st = State.Suffix;
                }
                break;
            case CXTokenKind.CXToken_Punctuation:
                r.name ~= t.spelling;
                break;
            case CXTokenKind.CXToken_Keyword:
                if (t.spelling.among("operator"))
                    st = State.Done;
                else if (!t.spelling.among("virtual"))
                    r.name ~= (r.name.length == 0 ? "" : " ") ~ t.spelling;
                break;
            default:
            }
            break;
        case State.Suffix:
            switch (t.kind) {
            case CXTokenKind.CXToken_Punctuation:
                if (t.spelling.among("&", "*")) {
                    r.name ~= t.spelling;
                }
                else
                    st = State.Done;
                break;
            case CXTokenKind.CXToken_Keyword:
                if (t.spelling.among("operator"))
                    st = State.Done;
                else
                    r.name ~= " " ~ t.spelling;
                break;
            default:
            }
            break;
        case State.Done: // do nothing
            break;
        }
    }

    return r;
}

private:

/** The name of the type is retrieved from the token it is derived from.
 *
 * Needed in those cases a Diagnostic error occur complaining about unknown type name.
 */
string nameFromToken(Cursor type) {
    import clang.Token : toString;

    auto tokens = type.tokens();
    string name;

    trace(tokens.length, " ", tokens.toString, " ", type.spelling);

    foreach (t; tokens) {
        trace(clang.Token.toString(t));
        switch (t.spelling) {
        case "":
            break;
        case "const":
            break;
        default:
            if (name.length == 0) {
                name = t.spelling;
            }
        }
    }

    return name;
}

TypeKind translateTypedef(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Typedef);
}
body {
    TypeKind result;

    if (type.isConst) {
        result.isConst = true;
        result.name = "const ";
    }

    result.name ~= type.spelling;

    return result;
}

string translateUnexposed(Type type, bool rewriteIdToObject)
in {
    assert(type.kind == CXTypeKind.CXType_Unexposed);
}
body {
    auto declaration = type.declaration;

    if (declaration.isValid)
        return translateType(declaration.type).name;

    else
        return translateCursorType(type.kind);
}

string translateConstantArray(Type type, bool rewriteIdToObject)
in {
    assert(type.kind == CXTypeKind.CXType_ConstantArray);
}
body {
    auto array = type.array;
    auto elementType = translateType(array.elementType).name;

    return elementType ~ '[' ~ to!string(array.size) ~ ']';
}

TypeKind translatePointer(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Pointer);
}
body {
    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    TypeKind result;
    result.isPointer = true;

    if (valueTypeIsConst(type)) {
        result.isConst = true;
        result.name = "const ";
    }

    result.name ~= translateType(type.pointeeType).name ~ "*";

    return result;
}

TypeKind translateReference(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_LValueReference);
}
body {
    static bool valueTypeIsConst(Type type) {
        auto pointee = type.pointeeType;

        while (pointee.kind == CXTypeKind.CXType_Pointer)
            pointee = pointee.pointeeType;

        return pointee.isConst;
    }

    TypeKind result;
    result.isRef = true;

    if (valueTypeIsConst(type)) {
        result.isConst = true;
        result.name = "const ";
    }

    result.name ~= translateType(type.pointeeType).name ~ "&";

    return result;
}

//string translateFunctionPointerType (Type type)
//    in
//{
//    assert(type.kind == CXTypeKind.CXType_BlockPointer || type.isFunctionPointerType);
//}
//body
//{
//    auto func = type.pointeeType.func;
//
//    Parameter[] params;
//    params.reserve(func.arguments.length);
//
//    foreach (type ; func.arguments)
//        params ~= Parameter(translateType(type));
//
//    auto resultType = translateType(func.resultType);
//
//    return translateFunction(resultType, "function", params, func.isVariadic, new String);
//}

string translateCursorType(CXTypeKind kind) {
    with (CXTypeKind) switch (kind) {
    case CXType_Invalid:
        return "<unimplemented>";
    case CXType_Unexposed:
        return "<unimplemented>";
    case CXType_Void:
        return "void";
    case CXType_Bool:
        return "bool";
    case CXType_Char_U:
        return "<unimplemented>";
    case CXType_UChar:
        return "ubyte";
    case CXType_Char16:
        return "wchar";
    case CXType_Char32:
        return "dchar";
    case CXType_UShort:
        return "ushort";
    case CXType_UInt:
        return "uint";

    case CXType_ULong:
        //includeHandler.addCompatible();
        return "c_ulong";

    case CXType_ULongLong:
        return "ulong";
    case CXType_UInt128:
        return "<unimplemented>";
    case CXType_Char_S:
        return "char";
    case CXType_SChar:
        return "byte";
    case CXType_WChar:
        return "wchar";
    case CXType_Short:
        return "short";
    case CXType_Int:
        return "int";

    case CXType_Long:
        //includeHandler.addCompatible();
        return "c_long";

    case CXType_LongLong:
        return "long";
    case CXType_Int128:
        return "<unimplemented>";
    case CXType_Float:
        return "float";
    case CXType_Double:
        return "double";
    case CXType_LongDouble:
        return "real";
    case CXType_NullPtr:
        return "null";
    case CXType_Overload:
        return "<unimplemented>";
    case CXType_Dependent:
        return "<unimplemented>";
    case CXType_Complex:
        return "<unimplemented>";
    case CXType_Pointer:
        return "<unimplemented>";
    case CXType_BlockPointer:
        return "<unimplemented>";
    case CXType_LValueReference:
        return "<unimplemented>";
    case CXType_RValueReference:
        return "<unimplemented>";
    case CXType_Record:
        return "<unimplemented>";
    case CXType_Enum:
        return "<unimplemented>";
    case CXType_Typedef:
        return "<unimplemented>";
    case CXType_FunctionNoProto:
        return "<unimplemented>";
    case CXType_FunctionProto:
        return "<unimplemented>";
    case CXType_Vector:
        return "<unimplemented>";
    default:
        assert(0, "Unhandled type kind " ~ to!string(kind));
    }
}
