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
import clang.Token;
import clang.Type;

import translator.Translator;

struct TypeKind {
    string name;
    string prefix; // const
    string suffix; // *, &, **
    bool isConst;
    bool isRef;
    bool isPointer;
}

string toString(in TypeKind type) {
    return format("%s%s%s", type.prefix.length == 0 ? "" : type.prefix ~ " ", type.name,
        type.suffix);
}

/** Translate a clang CXTypeKind to a string representation.
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
                result.name = translateTypedef(type);
                break;

            case CXType_Record:
            case CXType_Enum:
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
                result.name = translateCursorType(type.kind);
            }
        }
    }

    return result;
}

private:

string translateTypedef(Type type)
in {
    assert(type.kind == CXTypeKind.CXType_Typedef);
}
body {
    auto spelling = type.spelling;

    with (CXTypeKind) switch (spelling) {
    case "BOOL":
        return translateCursorType(CXType_Bool);

    case "int64_t":
        return translateCursorType(CXType_LongLong);
    case "int32_t":
        return translateCursorType(CXType_Int);
    case "int16_t":
        return translateCursorType(CXType_Short);
    case "int8_t":
        return "byte";

    case "uint64_t":
        return translateCursorType(CXType_ULongLong);
    case "uint32_t":
        return translateCursorType(CXType_UInt);
    case "uint16_t":
        return translateCursorType(CXType_UShort);
    case "uint8_t":
        return translateCursorType(CXType_UChar);

    case "size_t":
    case "ptrdiff_t":
    case "sizediff_t":
        return spelling;

    case "wchar_t":
        auto kind = type.canonicalType.kind;

        if (kind == CXType_Int)
            return "dchar";

        else if (kind == CXType_Short)
            return "wchar";
        break;

    default:
        break;
    }

    return spelling;
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
    result.name = translateType(type.pointeeType).name;
    result.isPointer = true;
    result.suffix = "*";

    if (valueTypeIsConst(type)) {
        result.isConst = true;
        result.prefix = "const";
    }

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
    result.name = translateType(type.pointeeType).name;
    result.isRef = true;
    result.suffix = "&";

    if (valueTypeIsConst(type)) {
        result.isConst = true;
        result.prefix = "const";
    }

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
