/**
 * Copyright: Copyright (c) 2012 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 29, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */

module clang.Visitor;

import clang.c.index;
import clang.Cursor;
import clang.TranslationUnit;

struct Visitor {
    alias Delegate = int delegate(ref Cursor, ref Cursor);
    alias OpApply = int delegate(Delegate dg);

    private Cursor cursor;

    this(Cursor cursor) {
        this.cursor = cursor;
    }

    int opApply(Delegate dg) {
        auto data = OpApplyData(dg, cursor.translationUnit);
        clang_visitChildren(cursor, &visitorFunction, cast(CXClientData)&data);

        return data.returnCode;
    }

private:

    extern (C) static CXChildVisitResult visitorFunction(CXCursor cursor,
        CXCursor parent, CXClientData data) {
        auto tmp = cast(OpApplyData*) data;

        with (CXChildVisitResult) {
            auto dCursor = Cursor(tmp.tu, cursor);
            auto dParent = Cursor(tmp.tu, parent);
            auto r = tmp.dg(dCursor, dParent);
            tmp.returnCode = r;
            return r ? CXChildVisit_Break : CXChildVisit_Continue;
        }
    }

    static struct OpApplyData {
        int returnCode;
        Delegate dg;
        TranslationUnit tu;

        this(Delegate dg, TranslationUnit tu) {
            this.dg = dg;
            this.tu = tu;
        }
    }

    template Constructors() {
        private Visitor visitor;

        this(Visitor visitor) {
            this.visitor = visitor;
        }

        this(Cursor cursor) {
            visitor = Visitor(cursor);
        }
    }
}

struct DeclarationVisitor {
    mixin Visitor.Constructors;

    int opApply(Visitor.Delegate dg) {
        foreach (cursor, parent; visitor) {
            if (cursor.isDeclaration) {
                if (auto result = dg(cursor, parent)) {
                    return result;
                }
            }
        }

        return 0;
    }
}

struct TypedVisitor(CXCursorKind kind) {
    private Visitor visitor;

    this(Visitor visitor) {
        this.visitor = visitor;
    }

    this(Cursor cursor) {
        this.visitor = Visitor(cursor);
    }

    int opApply(Visitor.Delegate dg) {
        foreach (cursor, parent; visitor) {
            if (cursor.kind == kind) {
                if (auto result = dg(cursor, parent)) {
                    return result;
                }
            }
        }

        return 0;
    }
}

alias ObjCInstanceMethodVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCInstanceMethodDecl);
alias ObjCClassMethodVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCClassMethodDecl);
alias ObjCPropertyVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCPropertyDecl);
alias ObjCProtocolVisitor = TypedVisitor!(CXCursorKind.CXCursor_ObjCProtocolRef);

struct ParamVisitor {
    mixin Visitor.Constructors;

    int opApply(int delegate(ref ParamCursor) dg) {
        foreach (cursor, parent; visitor) {
            if (cursor.kind == CXCursorKind.CXCursor_ParmDecl) {
                auto paramCursor = ParamCursor(cursor);

                if (auto result = dg(paramCursor))
                    return result;
            }
        }

        return 0;
    }

    @property size_t length() {
        auto type = Cursor(visitor.cursor).type;

        if (type.isValid)
            return type.func.arguments.length;

        else {
            size_t i;

            foreach (_; this)
                i++;

            return i;
        }
    }

    @property bool any() {
        return length > 0;
    }

    @property bool isEmpty() {
        return !any;
    }

    @property ParamCursor first() {
        assert(any, "Cannot get the first parameter of an empty parameter list");

        foreach (c; this)
            return c;

        assert(0, "Cannot get the first parameter of an empty parameter list");
    }
}
