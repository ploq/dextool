/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// Copyright: Copyright (c) 2012 Jacob Carlborg. All rights reserved.
/// Version: Initial created: Jan 30, 2012
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
module translator.Type;

import std.array;
import std.conv;
import std.string;
import logger = std.experimental.logger;

import clang.c.index;
import clang.Cursor;
import clang.Token;
import clang.Type;

struct TypeKind {
    string name;
    bool isConst;
    bool isRef;
    bool isPointer;
}

string toString(const TypeKind type) {
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
    import std.algorithm;
    import std.array;

    TypeKind result;

    auto tmp_c = type.declaration;
    auto tmp_t = tmp_c.typedefUnderlyingType;
    logger.trace(format("%s %s %s %s c:%s t:%s", type.spelling,
        to!string(type.kind), tmp_c.spelling, abilities(tmp_t), abilities(tmp_c), abilities(type)));

    with (CXTypeKind) {
        if (type.kind == CXType_BlockPointer || type.isFunctionPointerType)
            logger.error("Implement missing translation of function pointer");
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
                result.name = type.spelling;
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
            case CXType_FunctionProto:
                result.name = type.spelling.filter!(a => !a.among('(', ')')).cache.map!(
                    a => cast(char) a).array.strip(' ');
                break;

            default:
                logger.trace(format("%s|%s|%s|%s", type.kind, type.declaration,
                    type.isValid, type.typeKindSpelling));
                result.name = type.spelling;
            }
        }
    }
    logger.trace(result);

    return result;
}

TypeKind analyzeType(Type type) {
    import std.algorithm;
    import std.array;

    TypeKind result = toProperty(type);

    string t = type.spelling;
    auto name = t.filter!(a => !a.among('&', '*')).cache().map!(a => cast(char) a).array().splitter(
        ' ').filter!(a => !a.among("const")).cache().array().join;

    result.name = cast(string) name;
    return result;
}

/** Extract properties from a Cursor for a Type like const, pointer, reference.
 * Params:
 *  cursor = A cursor that have a type property.
 */
TypeKind toProperty(Cursor cursor) {
    return cursor.type.toProperty;
}

/** Extract properties from a Type like const, pointer, reference.
 * Params:
 *  type = A cursor that have a type property.
 */
TypeKind toProperty(Type type) {
    TypeKind result;

    if (type.isConst) {
        result.isConst = true;
    }

    if (type.declaration.isReference) {
        result.isRef = true;
    }

    if (type.kind == CXTypeKind.CXType_Pointer) {
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

    logger.trace(clang.SourceRange.toString(cursor.extent));

    enum State {
        Prefix,
        Suffix,
        Done
    }

    TypeKind r = cursor.toProperty();
    auto tokens = cursor.tokens();
    // name of the cursors identifier but NOT the type.
    auto cursor_identifier = cursor.spelling;
    logger.trace(tokens.length, "|", tokens.toString, "|",
        cursor.type.spelling, "|", cursor_identifier);

    State st;
    foreach (t; tokens) {
        logger.trace(clang.Token.toString(t), " ", text(st));

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
                if (t.spelling.among("(", ")", ","))
                    break;
                r.name ~= t.spelling;
                if (t.spelling == "*")
                    r.isPointer = true;
                else if (t.spelling == "&")
                    r.isRef = true;
                break;
            case CXTokenKind.CXToken_Keyword:
                if (t.spelling == "const")
                    r.isConst = true;
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
                    // TODO ugly... must be a better way.
                    if (t.spelling == "*")
                        r.isPointer = true;
                    else if (t.spelling == "&")
                        r.isRef = true;
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

    logger.trace(r);
    return r;
}

private:

enum keywords = ["operator", "virtual", "const"];
enum operators = ["(", ")", "*", "&"];

/** The name of the type is retrieved from the token it is derived from.
 *
 * Needed in those cases a Diagnostic error occur complaining about unknown type name.
 */
string nameFromToken(Cursor type) {
    import clang.Token : toString;

    auto tokens = type.tokens();
    string name;

    logger.trace(tokens.length, " ", tokens.toString, " ", type.spelling);

    foreach (t; tokens) {
        logger.trace(clang.Token.toString(t));
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
    }

    result.name = type.spelling;

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
    }

    result.name = translateType(type.pointeeType).name ~ "*";

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
    }

    result.name = translateType(type.pointeeType).name ~ "&";
    //result.name = type.spelling;

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
        //case CXType_ObjCId: return rewriteIdToObjcObject ? "ObjcObject" : "id";
    case CXType_ObjCId:
        return "ObjcObject";
    case CXType_ObjCClass:
        return "Class";
    case CXType_ObjCSel:
        return "SEL";

    case CXType_Complex:
    case CXType_Pointer:
    case CXType_BlockPointer:
    case CXType_LValueReference:
    case CXType_RValueReference:
    case CXType_Record:
    case CXType_Enum:
    case CXType_Typedef:
    case CXType_FunctionNoProto:
    case CXType_FunctionProto:
    case CXType_Vector:
    case CXType_IncompleteArray:
    case CXType_VariableArray:
    case CXType_DependentSizedArray:
    case CXType_MemberPointer:
        return "<unimplemented>";

    default:
        assert(0, "Unhandled type kind " ~ to!string(kind));
    }
}
