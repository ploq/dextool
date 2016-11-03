/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.graphml;

import std.format : FormatSpec;
import std.traits : isSomeString;
import std.typecons : scoped, Tuple, Nullable, Flag, Yes;
import logger = std.experimental.logger;

import cpptooling.analyzer.kind : resolveCanonicalType, resolvePointeeType;
import cpptooling.analyzer.type : TypeKindAttr, TypeKind, TypeAttr,
    toStringDecl;
import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.data.symbol.container : Container;
import cpptooling.data.type : CppAccess;
import cpptooling.utility.unqual : Unqual;
import cpptooling.utility.hash : makeHash;

version (unittest) {
    import unit_threaded;
} else {
    private struct Name {
        string name_;
    }
}

static import cpptooling.data.class_classification;

private ulong nextEdgeId()() {
    static ulong next = 0;
    return next++;
}

@safe interface Controller {
}

@safe interface Parameters {
}

/// Data produced by the backend to be handled by the frontend.
@safe interface Products {
    import application.types : FileName;

    /** Put content, by appending, to specified file.
     *
     * Params:
     *   fname = filename
     *   content = slice to write
     */
    void put(FileName fname, const(char)[] content);
}

final class GraphMLAnalyzer(ReceiveT) : Visitor {
    import cpptooling.analyzer.clang.ast : TranslationUnit, ClassDecl, VarDecl,
        FunctionDecl, Namespace, UnexposedDecl, StructDecl, CompoundStmt,
        Constructor, Destructor, CXXMethod;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl, analyzeClassStructDecl, analyzeTranslationUnit;
    import cpptooling.data.representation : CppRoot, CppNs, CFunction,
        CxReturnType;
    import cpptooling.data.symbol.container : Container;
    import cpptooling.data.type : LocationTag, Location;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;
    mixin generateIndentIncrDecr;

    private {
        ReceiveT recv;
        Controller ctrl;
        Parameters params;
        Products prod;
        Container* container;

        CppNs[] scope_stack;
    }

    this(ReceiveT recv, Controller ctrl, Parameters params, Products prod, ref Container container) {
        this.recv = recv;
        this.ctrl = ctrl;
        this.params = params;
        this.prod = prod;
        this.container = &container;
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char formatSpec) const {
        container.toString(w, formatSpec);
    }

    override string toString() @safe const {
        import std.exception : assumeUnique;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    override void visit(const(TranslationUnit) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeTranslationUnit(v, *container, indent);
        recv.put(result);

        v.accept(this);
    }

    override void visit(const(UnexposedDecl) v) {
        mixin(mixinNodeLog!());

        // An unexposed may be:

        // extern "C" void func_c_linkage();
        // UnexposedDecl "" extern "C" {...
        //   FunctionDecl "fun_c_linkage" void func_c_linkage
        v.accept(this);
    }

    override void visit(const(VarDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeVarDecl(v, *container, indent);

        if (scope_stack.length == 0) {
            recv.put(result);
        } else {
            recv.put(result, scope_stack);
        }
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, *container, indent);
        recv.put(result);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());

        () @trusted{ scope_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            scope_stack = scope_stack[0 .. $ - 1];

        // fill the namespace with content from the analyse
        v.accept(this);
    }

    // === Class and Struct ===

    /** Implicit promise that THIS method will output the class node after the
     * class has been classified.
     */
    override void visit(const(ClassDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeClassStructDecl(v, *container, indent + 1);
        auto style = visitClassStruct(v, result.type);
        style.label = result.name;
        recv.put(result, scope_stack, style);
    }

    override void visit(const(StructDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeClassStructDecl(v, *container, indent + 1);
        auto style = visitClassStruct(v, result.type);
        style.label = result.name;
        recv.put(result, scope_stack, style);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());
        visitClassStructMethod(v);
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());
        visitClassStructMethod(v);
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());
        visitClassStructMethod(v);
    }

    private auto visitClassStruct(T)(const(T) v, TypeKindAttr type) @trusted {
        import std.algorithm : map, joiner;
        import cpptooling.data.type : AccessType;

        foreach (loc; container.find!LocationTag(type.kind.usr).map!(a => a.any).joiner) {
            //if (!ctrl.doFile(loc.file, loc.file)) {
            //    return;
            //}
        }

        static if (is(T == ClassDecl)) {
            auto access_init = AccessType.Private;
        } else {
            auto access_init = AccessType.Public;
        }

        auto visitor = scoped!(ClassVisitor!(ReceiveT))(type, scope_stack,
                access_init, ctrl, recv, *container, indent + 1);
        v.accept(visitor);

        return visitor.style;
    }

    private auto visitClassStructMethod(T)(const(T) v) {
        import std.algorithm : among;
        import deimos.clang.index : CXCursorKind;

        auto parent = v.cursor.semanticParent;

        // can't handle ClassTemplates etc yet
        if (!parent.kind.among(CXCursorKind.CXCursor_ClassDecl, CXCursorKind.CXCursor_StructDecl)) {
            return;
        }

        auto result = analyzeClassStructDecl(parent, *container, indent);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(result.type, ctrl,
                    recv, *container, indent + 1);
            v.accept(visitor);
        }();
    }
}

/**
 *
 * The $(D ClassVisitor) do not know when the analyze is finished.
 * Therefore from the viewpoint of $(D ClassVisitor) classification is an
 * ongoing process. It is the responsibility of the caller of $(D
 * ClassVisitor) to use the final result of the classification together with
 * the style.
 */
private final class ClassVisitor(ReceiveT) : Visitor {
    import std.algorithm : map, copy, each, joiner;
    import std.array : Appender;
    import std.conv : to;
    import std.typecons : scoped, TypedefType, NullableRef;

    import cpptooling.analyzer.clang.ast : ClassDecl, StructDecl,
        CXXBaseSpecifier, Constructor, Destructor, CXXMethod, FieldDecl,
        CXXAccessSpecifier;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeClassDecl,
        analyzeStructDecl, analyzeConstructor, analyzeDestructor,
        analyzeCXXMethod, analyzeFieldDecl, analyzeCXXBaseSpecified,
        toAccessType, ClassDeclResult;
    import cpptooling.data.type : MemberVirtualType;
    import cpptooling.data.representation : CppNsStack, CppNs, AccessType,
        CppAccess, CppDtor, CppCtor, CppMethod;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    import cpptooling.data.class_classification : ClassificationState = State;
    import cpptooling.data.class_classification : classifyClass;
    import cpptooling.data.class_classification : MethodKind;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /** Type representation of this class.
     * Used as the source of the outgoing relations from this class.
     */
    TypeKindAttr this_;

    NodeStyle!UMLClassNode style;

    private {
        Controller ctrl;
        NullableRef!ReceiveT recv;

        Container* container;
        CppNsStack scope_stack;
        CppAccess access;

        /// If the class has any members.
        Flag!"hasMember" hasMember;

        /** Classification of the class.
         * Affected by methods.
         */
        ClassificationState classification;
    }

    this(ref const(TypeKindAttr) this_, const(CppNs)[] reside_in_ns, AccessType init_access,
            Controller ctrl, ref ReceiveT recv, ref Container container, in uint indent) {
        this.ctrl = ctrl;
        this.recv = &recv;
        this.container = &container;
        this.indent = indent;
        this.scope_stack = CppNsStack(reside_in_ns.dup);

        this.access = CppAccess(init_access);
        this.classification = ClassificationState.Unknown;

        this.this_ = this_;
    }

    /**
     * Has hidden data dependencies on:
     *  - hasMember.
     *  - current state of classification.
     *
     * Will update:
     *  - the internal state classification
     *  - the style stereotype
     */
    private void updateClassification(MethodKind kind, MemberVirtualType virtual_kind) {
        this.classification = classifyClass(this.classification, kind,
                virtual_kind, this.hasMember);
        this.style.stereotype = this.classification.toInternal!StereoType;
    }

    /// Nested class definitions.
    override void visit(const(ClassDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeClassDecl(v, *container, indent + 1);

        scope_stack ~= CppNs(cast(string) result.name);
        scope (exit)
            scope_stack = scope_stack[0 .. $ - 1];

        auto style = visitClassStruct(v, result.type);
        style.label = result.name;
        recv.put(result, scope_stack, style);
    }

    override void visit(const(StructDecl) v) {
        mixin(mixinNodeLog!());
        auto result = analyzeStructDecl(v, *container, indent + 1);

        scope_stack ~= CppNs(cast(string) result.name);
        scope (exit)
            scope_stack = scope_stack[0 .. $ - 1];

        auto style = visitClassStruct(v, result.type);
        style.label = result.name;
        recv.put(result, scope_stack, style);
    }

    private auto visitClassStruct(T)(const(T) v, TypeKindAttr type) @trusted {
        import cpptooling.data.type : AccessType;

        static if (is(T == ClassDecl)) {
            auto access_init = AccessType.Private;
        } else {
            auto access_init = AccessType.Public;
        }

        auto visitor = scoped!(ClassVisitor!(ReceiveT))(type, scope_stack,
                AccessType.Private, ctrl, recv, *container, indent + 1);
        v.accept(visitor);

        return visitor.style;
    }

    /// Analyze the inheritance(s).
    override void visit(const(CXXBaseSpecifier) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeCXXBaseSpecified(v, *container, indent);

        recv.put(this_, result);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);

        auto tor = CppCtor(result.usr, result.name, result.params, access);
        style.methods ~= access.toInternal!string ~ tor.toString;

        recv.put(this_, result, access);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(this_, ctrl, recv,
                    *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeDestructor(v, *container, indent);
        updateClassification(MethodKind.Dtor, cast(MemberVirtualType) result.virtualKind);

        auto tor = CppDtor(result.usr, result.name, access, result.virtualKind);
        style.methods ~= access.toInternal!string ~ tor.toString;

        recv.put(this_, result, access);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(this_, ctrl, recv,
                    *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(CXXMethod) v) {
        mixin(mixinNodeLog!());
        import cpptooling.data.type : CppConstMethod;
        import cpptooling.data.representation : CppMethod;

        auto result = analyzeCXXMethod(v, *container, indent);

        auto method = CppMethod(result.type.kind.usr, result.name, result.params,
                result.returnType, access, CppConstMethod(result.isConst), result.virtualKind);
        style.methods ~= access.toInternal!string ~ method.toString;

        updateClassification(MethodKind.Method, cast(MemberVirtualType) result.virtualKind);

        recv.put(this_, result, access);

        () @trusted{
            auto visitor = scoped!(BodyVisitor!(ReceiveT))(this_, ctrl, recv,
                    *container, indent + 1);
            v.accept(visitor);
        }();
    }

    override void visit(const(FieldDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFieldDecl(v, *container, indent);

        style.attributes ~= access.toInternal!string ~ result.type.toStringDecl(
                cast(string) result.name);

        // TODO probably not necessary for classification to store it as a
        // member. Instead extend MethodKind to having a "Member".
        hasMember = Yes.hasMember;
        updateClassification(MethodKind.Unknown, MemberVirtualType.Unknown);

        recv.put(this_, result, access);
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        import std.conv : to;

        mixin(mixinNodeLog!());
        access = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }
}

/** Visit a function or method body.
 *
 */
private final class BodyVisitor(ReceiveT) : Visitor {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.typecons;

    import cpptooling.analyzer.clang.ast;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper;
    import cpptooling.data.representation;
    import cpptooling.utility.clang : logNode, mixinNodeLog;

    alias visit = Visitor.visit;

    mixin generateIndentIncrDecr;

    /** Type representation of parent.
     * Used as the source of the outgoing relations from this class.
     */
    TypeKindAttr parent;

    private {
        Controller ctrl;
        NullableRef!ReceiveT recv;

        Container* container;
    }

    this(const(TypeKindAttr) parent, Controller ctrl, ref ReceiveT recv,
            ref Container container, in uint indent) {
        this.parent = parent;
        this.ctrl = ctrl;
        this.recv = &recv;
        this.container = &container;
        this.indent = indent;
    }

    override void visit(const(Declaration) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Expression) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(Statement) v) {
        mixin(mixinNodeLog!());
        v.accept(this);
    }

    override void visit(const(CallExpr) v) {
        mixin(mixinNodeLog!());
        import deimos.clang.index : CXCursorKind;

        auto c_func = v.cursor.referenced;

        if (c_func.kind == CXCursorKind.CXCursor_FunctionDecl) {
            auto result = analyzeFunctionDecl(c_func, *container, indent);
            recv.put(parent, result);
        }

        v.accept(this);
    }

    override void visit(const(DeclRefExpr) v) {
        mixin(mixinNodeLog!());
        import deimos.clang.index : CXCursorKind;
        import cpptooling.analyzer.clang.utility : isGlobalOrNamespaceScope;

        auto c_ref = v.cursor.referenced;

        // accessing a global
        if (c_ref.kind == CXCursorKind.CXCursor_VarDecl && c_ref.isGlobalOrNamespaceScope) {
            auto result = analyzeVarDecl(c_ref, *container, indent);
            recv.put(parent, result);
        }

        v.accept(this);
    }

    //override void visit(const(VarDecl) v) {
    //    mixin(mixinNodeLog!());
    //}
}

private T toInternal(T, S)(S value) @safe pure nothrow @nogc 
        if (isSomeString!T && is(S == CppAccess)) {
    import cpptooling.data.representation : AccessType;

    final switch (value) {
    case AccessType.Private:
        return "-";
    case AccessType.Protected:
        return "#";
    case AccessType.Public:
        return "+";
    }
}

private enum ColorKind {
    none,
    file,
    global,
    globalConst,
    globalStatic,
    namespace,
    func,
    class_
}

private struct FillColor {
    string color1;
    string color2;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;

        if (color1.length > 0) {
            formattedWrite(w, `color="#%s"`, color1);
        }

        if (color2.length > 0) {
            formattedWrite(w, ` color2="#%s"`, color2);
        }
    }
}

private FillColor toInternal(ColorKind kind) @safe pure nothrow @nogc {
    final switch (kind) {
    case ColorKind.none:
        return FillColor(null, null);
    case ColorKind.file:
        return FillColor("CCFFCC", null);
    case ColorKind.global:
        return FillColor("FF33FF", null);
    case ColorKind.globalConst:
        return FillColor("FFCCFF", null);
    case ColorKind.globalStatic:
        return FillColor("FFD9D2", "FF66FF");
    case ColorKind.namespace:
        return FillColor("FFCCCC", null);
    case ColorKind.func:
        return FillColor("FF6600", null);
    case ColorKind.class_:
        return FillColor("FFCC33", null);
    }
}

private @safe struct ValidNodeId {
    import cpptooling.data.type : USRType;

    size_t payload;
    alias payload this;

    this(string usr) {
        payload = makeHash(cast(string) usr);
    }

    this(USRType usr) {
        this(cast(string) usr);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formatValue;

        formatValue(w, payload, formatSpec);
    }
}

private enum StereoType {
    None,
    Abstract,
    Interface,
}

private struct ShapeNode {
    string label;
    ColorKind color;

    private enum baseHeight = 20;
    private enum baseWidth = 140;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char = "%s") const {
        import std.format : formattedWrite;

        formattedWrite(w, `<y:Geometry height="%s" width="%s"/>`, baseHeight, baseWidth);
        if (color != ColorKind.none) {
            formattedWrite(w, `<y:Fill %s transparent="false"/>`, color.toInternal);
        }
        formattedWrite(w,
                `<y:NodeLabel autoSizePolicy="node_size" configuration="CroppingLabel"><![CDATA[%s]]></y:NodeLabel>`,
                label);
    }
}

private struct UMLClassNode {
    string label;
    StereoType stereotype;
    string[] attributes;
    string[] methods;

    private enum baseHeight = 28;

    void toString(Writer)(scope Writer w) const {
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range.primitives : put;

        formattedWrite(w, `<y:NodeLabel><![CDATA[%s]]></y:NodeLabel>`, label);

        formattedWrite(w, `<y:Geometry height="%s" width="100.0"/>`,
                stereotype == StereoType.None ? baseHeight : baseHeight * 2);
        put(w, `<y:Fill color="#FFCC00" transparent="false"/>`);

        formattedWrite(w, `<y:UML clipContent="true" omitDetails="false" stereotype="%s">`,
                stereotype == StereoType.None ? "" : stereotype.to!string());

        if (attributes.length > 0) {
            put(w, `<y:AttributeLabel>`);
        }
        foreach (attr; attributes) {
            ccdataWrap(w, attr);
            put(w, "\n");
        }
        if (attributes.length > 0) {
            put(w, `</y:AttributeLabel>`);
        }

        if (methods.length > 0) {
            put(w, `<y:MethodLabel>`);
        }
        foreach (method; methods) {
            ccdataWrap(w, method);
            put(w, "\n");
        }
        if (methods.length > 0) {
            put(w, `</y:MethodLabel>`);
        }

        put(w, `</y:UML>`);
    }
}

@Name("Should instantiate all NodeStyles")
unittest {
    import std.array : appender;
    import std.meta : AliasSeq;

    auto app = appender!string();

    foreach (T; AliasSeq!(ShapeNode, UMLClassNode)) {
        {
            NodeStyle!T node;
            node.toString(app, FormatSpec!char("%s"));
        }
    }
}

private auto makeShapeNode(string label, ColorKind color = ColorKind.none) {
    return NodeStyle!ShapeNode(ShapeNode(label, color));
}

private auto makeUMLClassNode(string label) {
    return NodeStyle!UMLClassNode(UMLClassNode(label));
}

/** Node style in GraphML.
 *
 * Intented to carry metadata and formatting besides a generic label.
 */
private struct NodeStyle(PayloadT) {
    import std.format : formattedWrite;

    private {
        PayloadT payload;
    }

    alias payload this;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char spec) const {
        import std.range.primitives : put;

        enum graph_node = PayloadT.stringof;

        put(w, `<data key="d5">`);
        formattedWrite(w, "<y:%s>%s</y:%s>", graph_node, payload, graph_node);
        put(w, "</data>");
    }

}

private void ccdataWrap(Writer, ARGS...)(scope Writer w, auto ref ARGS args) {
    import std.range.primitives : put;

    put(w, `<![CDATA[`);
    foreach (arg; args) {
        static if (__traits(hasMember, typeof(arg), "toString")) {
            arg.toString(w, FormatSpec!char("%s"));
        } else {
            put(w, arg);
        }
    }
    put(w, `]]>`);
}

private void xmlComment(RecvT, CharT)(ref RecvT recv, CharT v) {
    import std.format : formattedWrite;

    formattedWrite(recv, "<!-- %s -->\n", v);
}

private struct XmlNode(UrlT, StyleT) {
    import std.typecons : Nullable;
    import cpptooling.analyzer.kind : TypeAttr;

    Nullable!UrlT url;
    Nullable!string kind;
    Nullable!TypeAttr typeAttr;
    Nullable!string signature;
    Nullable!StyleT style;

    void renderOpen(RecvT, IdT)(ref RecvT recv, IdT id) {
        import std.conv : to;
        import std.format : formattedWrite;
        import std.range.primitives : put;

        auto id_ = ValidNodeId(id);

        debug {
            // printing the raw identifiers to make it easier to debug
            formattedWrite(recv, `<!-- %s -->`, cast(string) id);
        }

        formattedWrite(recv, `<node id="%s">`, id_);

        if (!url.isNull) {
            put(recv, `<data key="d3">`);
            ccdataWrap(recv, url.file);
            put(recv, "</data>");

            put(recv, `<data key="d4">`);
            ccdataWrap(recv, "Line:", url.line.to!string, " Column:", url.column.to!string);
            put(recv, "</data>");
        }

        if (!kind.isNull) {
            put(recv, `<data key="d6">`);
            ccdataWrap(recv, kind.get);
            put(recv, "</data>");
        }

        if (!typeAttr.isNull) {
            put(recv, `<data key="d7">`);
            typeAttr.get.toString(recv, FormatSpec!char("%s"));
            put(recv, "</data>");
        }

        if (!signature.isNull) {
            put(recv, `<data key="d8">`);
            ccdataWrap(recv, signature.get);
            put(recv, "</data>");
        }

        if (!style.isNull) {
            style.get.toString(recv, FormatSpec!char("%s"));
        }
    }

    void renderClose(RecvT)(ref RecvT recv) {
        import std.range.primitives : put;

        put(recv, "</node>\n");
    }

    void render(RecvT, IdT)(ref RecvT recv, IdT id) {
        renderOpen(recv, id);
        renderClose(recv);
    }
}

private enum EdgeKind {
    Directed,
    Generalization
}

private void xmlEdge(RecvT, SourceT, TargetT)(ref RecvT recv, SourceT src,
        TargetT target, EdgeKind kind) @safe {
    import std.conv : to;
    import std.format : formattedWrite;
    import std.range.primitives : put;

    auto src_ = ValidNodeId(src);
    auto target_ = ValidNodeId(target);

    debug {
        // printing the raw identifiers to make it easier to debug
        formattedWrite(recv, `<!-- %s - %s -->`, cast(string) src, cast(string) target);
    }

    final switch (kind) with (EdgeKind) {
    case Directed:
        formattedWrite(recv, `<edge id="e%s" source="%s" target="%s"/>`,
                nextEdgeId.to!string, src_, target_);
        break;
    case Generalization:
        formattedWrite(recv, `<edge id="e%s" source="%s" target="%s">`,
                nextEdgeId.to!string, src_, target_);
        put(recv,
                `<data key="d9"><y:PolyLineEdge><y:Arrows source="none" target="white_delta"/></y:PolyLineEdge></data>`);
        put(recv, `</edge>`);
        break;
    }

    put(recv, "\n");
}

private T toInternal(T, S)(S value) @safe pure nothrow @nogc 
        if (is(T == StereoType) && is(S == cpptooling.data.class_classification.State)) {
    final switch (value) with (cpptooling.data.class_classification.State) {
    case Unknown:
    case Normal:
    case Virtual:
        return StereoType.None;
    case Abstract:
        return StereoType.Abstract;
    case VirtualDtor: // only one method, a d'tor and it is virtual
    case Pure:
        return StereoType.Interface;
    }
}

/** Deduct if the type is primitive from the point of view of TransformToXmlStream.
 *
 * Filtering out arrays or ptrs of primitive types as to not result in too much
 * noise.
 */
private bool isPrimitive(LookupT)(const TypeKind type, LookupT lookup) @safe nothrow {
    switch (type.info.kind) with (TypeKind.Info) {
    case Kind.primitive:
        return true;
    case Kind.array:
        foreach (ele; lookup.kind(type.info.element)) {
            return ele.info.kind == Kind.primitive;
        }
        return false;
    case Kind.pointer:
        foreach (ele; lookup.kind(type.info.pointee)) {
            return ele.info.kind == Kind.primitive;
        }
        return false;
    default:
        return false;
    }
}

import std.range : isOutputRange;

/** Transform analyze data to a xml stream.
 *
 * XML nodes must never be duplicated.
 * An edge source or target must be to nodes that exist.
 *
 * # Strategy `class`
 * The generation of a `node` is delayed as long as possible for a class
 * declaration in the hope of finding the definition.
 * The delay is implemented with a cache.
 * When finalize is called the cache is forcefully transformed to `nodes`.
 * Even those symbols that only have a declaration as location.
 */
class TransformToXmlStream(RecvXmlT, LookupT) if (isOutputRange!(RecvXmlT, char)) {
    import std.range : only;
    import std.typecons : NullableRef;

    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        ClassDeclResult, FieldDeclResult, CXXMethodResult, ConstructorResult,
        DestructorResult, VarDeclResult, FunctionDeclResult,
        TranslationUnitResult;
    import cpptooling.analyzer.type : TypeKindAttr, TypeKind, TypeAttr,
        toStringDecl;
    import cpptooling.data.type : USRType, LocationTag, Location, CppNs;
    import plugin.utility : MarkArray;

    private {
        struct TypeData {
            import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;

            alias Extra = TaggedAlgebraic!ExtraTagged;

            TypeKindAttr payload;
            Extra extra;

            alias payload this;

            struct Func {
                string identifier;
                string signature;
            }

            struct Type {
            }

            struct Record {
                string identifier;
            }

            struct Variable {
            }

            static union ExtraTagged {
                typeof(null) null_;
                Func func;
                Type type;
                Variable variable;
                Record record;
            }

            ///
            XmlNode!(Location, NodeStyle!ShapeNode) toXmlNode() const {
                import std.conv : to;

                XmlNode!(Location, NodeStyle!ShapeNode) data;

                data.kind = extra.kind.to!string();
                //data.kind = payload.kind.info.kind.to!string();
                data.typeAttr = payload.attr;

                final switch (extra.kind) with (Extra) {
                case Kind.func:
                    data.style = makeShapeNode(extra.identifier, ColorKind.func);
                    data.signature = extra.signature;
                    break;
                case Kind.type:
                    data.style = makeShapeNode(payload.kind.toStringDecl(TypeAttr.init));
                    data.signature = payload.toStringDecl;
                    break;
                case Kind.variable:
                    break;
                case Kind.record:
                    data.style = makeShapeNode(extra.identifier, ColorKind.class_);
                    break;
                case Kind.null_:
                    data.kind = null;
                    data.style = makeShapeNode(payload.kind.toStringDecl(TypeAttr.init));
                    data.signature = payload.toStringDecl;
                    break;
                }

                return data;
            }
        }

        MarkArray!TypeData type_cache;

        /// nodes may never be duplicated. If they are it is a violation of the
        /// data format.
        bool[USRType] streamed_nodes;
        /// Ensure that there are only ever one relation between two entities.
        /// It avoids the scenario (which is common) of thick patches of
        /// relations to common nodes.
        bool[USRType] streamed_edges;

        NullableRef!RecvXmlT recv;
        LookupT lookup;
    }

    this(ref RecvXmlT recv, LookupT lookup) {
        this.recv = &recv;
        this.lookup = lookup;
    }

@safe:

    ///
    void finalize() {
        if (type_cache.data.length == 0) {
            return;
        }

        debug {
            logger.tracef("%d nodes left in cache", type_cache.data.length);
            foreach (idx, ref n; type_cache.data) {
                logger.tracef("  %d: %s", idx + 1, n.kind.usr);
            }
        }

        void anyLocation(ref const(TypeData) type, ref const(LocationTag) loc) {
            if (type.kind.isPrimitive(lookup)) {
                return;
            }

            nodeIfMissing(streamed_nodes, recv, type.kind.usr, type, loc);
            debug logger.tracef("creating node %s", cast(string) type.kind.usr);
        }

        LocationCallback cb;
        cb.unknown = &anyLocation;
        cb.declaration = &anyLocation;
        cb.definition = &anyLocation;

        resolveLocation(cb, type_cache.data, lookup);
        type_cache.clear;
    }

    ///
    void put(ref const(TranslationUnitResult) result) {
        xmlComment(recv, result.fileName);

        // empty the cache if anything is left in it
        if (type_cache.data.length == 0) {
            return;
        }

        debug logger.tracef("%d nodes left in cache", type_cache.data.length);

        // ugly hack.
        // used by putDefinition
        // incremented in the foreach
        size_t idx = 0;

        void putDeclaration(ref const(TypeData) type, ref const(LocationTag) loc) {
            // hoping for the best that a definition is found later on.
        }

        void putDefinition(ref const(TypeData) type, ref const(LocationTag) loc) {
            if (!type.kind.isPrimitive(lookup)) {
                nodeIfMissing(streamed_nodes, recv, type.kind.usr, type, loc);
            }

            type_cache.markForRemoval(idx);
        }

        LocationCallback cb;
        cb.unknown = &putDeclaration;
        cb.declaration = &putDeclaration;
        cb.definition = &putDefinition;

        foreach (ref item; type_cache.data) {
            resolveLocation(cb, only(item), lookup);
            ++idx;
        }

        debug logger.tracef("%d nodes left in cache", type_cache.data.length);

        type_cache.doRemoval;
    }

    static ColorKind decideColor(ref const(VarDeclResult) result) {
        import cpptooling.data.type : StorageClass;

        auto color = ColorKind.global;
        if (result.type.attr.isConst) {
            color = ColorKind.globalConst;
        } else if (result.storageClass == StorageClass.Static) {
            color = ColorKind.globalStatic;
        }

        return color;
    }

    /** A free variable declaration.
     *
     * This method do NOT handle those inside a function/method/namespace.
     */
    void put(ref const(VarDeclResult) result) {
        Nullable!USRType file_usr = addFileNode(streamed_nodes, recv, result.location);
        addVarDecl(file_usr, result);
    }

    /** A free variable declaration in a namespace.
     *
     * TODO maybe connect the namespace to the file?
     */
    void put(ref const(VarDeclResult) result, CppNs[] ns)
    in {
        assert(ns.length > 0);
    }
    body {
        auto ns_usr = addNamespaceNode(streamed_nodes, recv, ns);
        addVarDecl(ns_usr, result);
    }

    private void addVarDecl(Nullable!USRType parent, ref const(VarDeclResult) result) {
        { // instance node
            XmlNode!(Location, NodeStyle!ShapeNode) node;
            node.url = result.location;
            node.typeAttr = result.type.attr;
            node.signature = result.type.toStringDecl(result.name);
            node.style = makeShapeNode(result.name, decideColor(result));
            nodeIfMissing(streamed_nodes, recv, result.instanceUSR, node);
        }

        if (!parent.isNull) {
            // connect namespace to instance
            addEdge(streamed_edges, recv, parent, result.instanceUSR);
        }

        // type node
        if (!result.type.kind.isPrimitive(lookup)) {
            putToCache(TypeData(result.type, TypeData.Extra(TypeData.Type())));
            addEdge(streamed_edges, recv, result.instanceUSR, result.type.kind.usr);
        }
    }

    /** Accessing a global.
     *
     * Assuming that src is already put in the cache.
     * Assuming that target is already in cache or will be in the future when
     * traversing the AST.
     * */
    void put(ref const(TypeKindAttr) src, ref const(VarDeclResult) result) {
        addEdge(streamed_edges, recv, src.kind.usr, result.instanceUSR);
    }

    ///
    void put(ref const(FunctionDeclResult) result) {
        import std.algorithm : map, filter, joiner;
        import cpptooling.data.representation : unpackParam;

        auto src = resolveCanonicalType(result.type.kind, result.type.attr, lookup).front;
        putToCache(TypeData(src, TypeData.Extra(TypeData.Func(cast(string) result.name,
                result.type.toStringDecl(result.name)))));

        {
            auto target = resolvePointeeType(result.returnType.kind, result.returnType.attr, lookup)
                .front;
            putToCache(target);
            edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
        }

        // dfmt off
        foreach (target; result.params
            .map!(a => a.unpackParam)
            .filter!(a => !a.isVariadic)
            .map!(a => a.type)
            .map!(a => resolvePointeeType(a.kind, a.attr, lookup))
            .joiner
            .map!(a => TypeKindAttr(a.kind, TypeAttr.init))) {
            putToCache(target);
            edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
        }
        // dfmt on
    }

    /** Calls from src to result.
     *
     * Assuming that src is already put in the cache.
     *
     * Only interested in the relation from src to the function.
     */
    void put(ref const(TypeKindAttr) in_src, ref const(FunctionDeclResult) result) {
        auto src = resolveCanonicalType(in_src.kind, in_src.attr, lookup).front;

        auto target = resolveCanonicalType(result.type.kind, result.type.attr, lookup).front;
        putToCache(TypeData(target, TypeData.Extra(TypeData.Func(cast(string) result.name,
                result.type.toStringDecl(result.name)))));

        edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
    }

    /**
     * Assuming that a node ClassDecl never resolve to _another_ type in turn,
     * like a typedef do.
     * If the assumption doesn't hold then the target for the edge from the
     * namespace to the class has to be changed to the one received from
     * putDeclaration or putDefinition.
     */
    void put(ref const(ClassDeclResult) result, CppNs[] ns, ref const(NodeStyle!UMLClassNode) style) {
        void putDeclaration(ref const(TypeData) type, ref const(LocationTag) loc) {
            putToCache(TypeData(type, TypeData.Extra(TypeData.Record(result.name))));
        }

        void putDefinition(ref const(TypeData) type, ref const(LocationTag) loc) {
            XmlNode!(LocationTag, NodeStyle!UMLClassNode) data;
            data.url = loc;
            // how do I copy the const struct?
            data.style = () @trusted{ return cast(NodeStyle!UMLClassNode) style; }();
            nodeIfMissing(streamed_nodes, recv, type.kind.usr, data);
        }

        LocationCallback cb;
        cb.unknown = &putDeclaration;
        cb.declaration = &putDeclaration;
        cb.definition = &putDefinition;

        resolveLocation(cb, only(TypeData(result.type)), lookup);

        auto ns_usr = addNamespaceNode(streamed_nodes, recv, ns);
        if (!ns_usr.isNull) {
            addEdge(streamed_edges, recv, ns_usr, result.type);
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result, in CppAccess access) {
        import std.algorithm : map, filter, joiner;
        import cpptooling.data.representation : unpackParam;

        // dfmt off
        foreach (target; result.params
            .map!(a => a.unpackParam)
            .filter!(a => !a.isVariadic)
            .map!(a => a.type)
            .map!(a => resolvePointeeType(a.kind, a.attr, lookup))
            .joiner
            .map!(a => TypeKindAttr(a.kind, TypeAttr.init))) {
            putToCache(target);
            edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
        }
        // dfmt on
    }

    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess access) {
        // do nothing
    }

    ///
    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess access) {
        import std.algorithm : map, filter, joiner;
        import cpptooling.data.representation : unpackParam;

        // dfmt off
        foreach (target; result.params
            .map!(a => a.unpackParam)
            .filter!(a => !a.isVariadic)
            .map!(a => a.type)
            .map!(a => resolvePointeeType(a.kind, a.attr, lookup))
            .joiner
            .map!(a => TypeKindAttr(a.kind, TypeAttr.init))) {
            putToCache(target);
            edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
        }
        // dfmt on
    }

    /** Relation of a class/struct to its fields.
     *
     * TODO remove the comment below. Incorrect.
     * Resolving a type for a FieldDecl inadvertently always change the USR.
     * Thus the edge that is formed must be for the type from putDeclaration or
     * putDefinition.
     */
    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess access) {
        if (result.type.kind.isPrimitive(lookup)) {
            return;
        }

        auto target = resolvePointeeType(result.type.kind, result.type.attr, lookup).front;
        putToCache(TypeKindAttr(target.kind, TypeAttr.init));

        edgeIfNotPrimitive(streamed_edges, recv, src, target, lookup);
    }

    /// Avoid code duplication by creating nodes via the type_cache.
    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
        putToCache(result.type);
        // by definition it can never be a primitive type so no check needed.
        addEdge(streamed_edges, recv, src.kind.usr, result.canonicalUSR, EdgeKind.Generalization);
    }

private:

    import std.range : ElementType;

    /** Used for callback to distinguish the type of location that has been
     * resolved.
     */
    struct LocationCallback {
        void delegate(ref const(TypeData) type, ref const(LocationTag) loc) @safe unknown;
        void delegate(ref const(TypeData) type, ref const(LocationTag) loc) @safe declaration;
        void delegate(ref const(TypeData) type, ref const(LocationTag) loc) @safe definition;
    }

    /** Resolve a type and its location.
     *
     * Performs a callback to either:
     *  - callback_def with the resolved type:s TypeKindAttr for the type and
     *    location of the definition.
     *  - callback_decl with the resolved type:s TypeKindAttr.
     * */
    static void resolveLocation(Range, LookupT)(LocationCallback callback,
            Range range, LookupT lookup)
            if (is(Unqual!(ElementType!Range) == TypeData) && __traits(hasMember,
                LookupT, "kind") && __traits(hasMember, LookupT, "location")) {
        import std.algorithm : map;
        import std.typecons : tuple;

        // dfmt off
        foreach (ref a; range
                 // a tuple of (TypeData, DeclLocation)
                 .map!(a => tuple(a, lookup.location(a.kind.usr)))) {
            // no location?
            if (a[1].length == 0) {
                LocationTag noloc;
                callback.unknown(a[0], noloc);
            }

            auto loc = a[1].front;

            if (loc.hasDefinition) {
                callback.definition(a[0], loc.definition);
            } else if (loc.hasDeclaration) {
                callback.declaration(a[0], loc.declaration);
            } else {
                // no location?
                LocationTag noloc;
                callback.unknown(a[0], noloc);
            }
        }
        // dfmt on
    }

    static auto toRelativePath(const LocationTag loc) {
        import std.path : relativePath;

        if (loc.kind == LocationTag.Kind.noloc) {
            return loc;
        }

        string rel;
        () @trusted{ rel = relativePath(loc.file); }();

        return LocationTag(Location(rel, loc.line, loc.column));
    }

    void putToCache(T)(const T data) {
        // lower the number of allocations by checking in the hash table.
        if (data.kind.usr in streamed_nodes) {
            return;
        }

        static if (is(T == TypeKindAttr)) {
            type_cache.put(TypeData(data, TypeData.Extra(TypeData.Type())));
        } else {
            type_cache.put(data);
        }
    }

    // The following functions result in xml data being written.

    static Nullable!USRType addNamespaceNode(NodeStoreT, RecvT)(ref NodeStoreT nodes,
            ref RecvT recv, CppNs[] ns) {
        if (ns.length == 0) {
            return Nullable!USRType();
        }

        import cpptooling.data.type : toStringNs;

        auto ns_usr = USRType(ns.toStringNs);

        XmlNode!(LocationTag, NodeStyle!ShapeNode) node;
        node.url = LocationTag(null);
        node.style = makeShapeNode(ns_usr, ColorKind.namespace);
        nodeIfMissing(nodes, recv, ns_usr, node);

        return Nullable!USRType(ns_usr);
    }

    static USRType addFileNode(NodeStoreT, RecvT, LocationT)(ref NodeStoreT nodes,
            ref RecvT recv, LocationT location) {
        auto file_usr = cast(USRType) location.file;

        if (file_usr !in nodes) {
            import std.path : baseName;

            auto file_label = location.file.baseName;
            auto file_loc = Location(location.file, 0, 0);

            XmlNode!(Location, NodeStyle!ShapeNode) node;
            node.url = file_loc;
            node.style = makeShapeNode(file_label, ColorKind.file);
            nodeIfMissing(nodes, recv, file_usr, node);
        }

        return file_usr;
    }

    static void nodeIfNotPrimitive(NodeStoreT, RecvT, LocationT, LookupT)(ref NodeStoreT nodes,
            ref RecvT recv, TypeKindAttr type, LocationT loc, LookupT lookup) {
        if (type.kind.isPrimitive(lookup)) {
            return;
        }

        nodeIfMissing(nodes, recv, type.kind.usr, type, loc);
    }

    /**
     * Params:
     *   nodes = a AA with USRType as key
     *   recv = the receiver of the xml data
     *   node_usr = the unique USR for the node
     *   node = either the TypeKindAttr of the node or a type supporting
     *          `.toString` taking a generic writer as argument.
     */
    static void nodeIfMissing(NodeStoreT, RecvT)(ref NodeStoreT nodes,
            ref RecvT recv, USRType node_usr, TypeData node, Location loc) {

        auto data = node.toXmlNode;
        data.url = loc;
        nodeIfMissing(nodes, recv, node_usr, data);
    }

    static void nodeIfMissing(NodeStoreT, RecvT, NodeT)(ref NodeStoreT nodes,
            ref RecvT recv, USRType node_usr, NodeT node) {
        if (node_usr in nodes) {
            return;
        }

        node.render(recv, cast(string) node_usr);
        nodes[node_usr] = true;
    }

    static void edgeIfNotPrimitive(EdgeStoreT, RecvT, LookupT)(ref EdgeStoreT edges,
            ref RecvT recv, TypeKindAttr src, TypeKindAttr target, LookupT lookup) {
        if (target.kind.info.kind == TypeKind.Info.Kind.null_
                || src.kind.isPrimitive(lookup) || target.kind.isPrimitive(lookup)) {
            return;
        }

        addEdge(edges, recv, src, target);
    }

    static void addEdge(EdgeStoreT, RecvT, SrcT, TargetT)(ref EdgeStoreT edges,
            ref RecvT recv, SrcT src, TargetT target, EdgeKind kind = EdgeKind.Directed) {
        string target_usr;
        static if (is(Unqual!TargetT == TypeKindAttr)) {
            if (target.kind.info.kind == TypeKind.Info.Kind.null_) {
                return;
            }

            target_usr = cast(string) target.kind.usr;
        } else {
            target_usr = cast(string) target;
        }

        string src_usr;
        static if (is(Unqual!SrcT == TypeKindAttr)) {
            src_usr = cast(string) src.kind.usr;
        } else {
            src_usr = cast(string) src;
        }

        // skip self edges
        if (target_usr == src_usr) {
            return;
        }

        // naive approach
        USRType edge_key = USRType(src_usr ~ target_usr);
        if (edge_key in edges) {
            return;
        }

        xmlEdge(recv, src_usr, target_usr, kind);
        edges[edge_key] = true;
    }
}
