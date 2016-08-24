/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.graphml;

import cpptooling.data.symbol.container;
import cpptooling.analyzer.clang.ast : Visitor;

@safe interface Controller {
}

@safe interface Parameters {
}

@safe interface Products {
}

final class GraphMLAnalyzer : Visitor {
    import std.typecons : scoped;

    import cpptooling.analyzer.clang.ast : VarDecl, FunctionDecl,
        TranslationUnit;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl;
    import cpptooling.data.representation : CppRoot;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    Container container;

    private {
        Controller ctrl;
        Parameters params;
        Products prod;
    }

    this(Controller ctrl, Parameters params, Products prod) {
        this.ctrl = ctrl;
        this.params = params;
        this.prod = prod;
    }

    override void visit(const(TranslationUnit) v) {
    }

    import std.format : FormatSpec;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char formatSpec) const {
        import std.format : formatValue;
        import std.range.primitives : put;

        formatValue(w, container, formatSpec);
    }

    override string toString() @safe const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }
}
