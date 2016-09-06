/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.graphml;

import std.traits : isSomeString;
import std.typecons : scoped, Tuple, Nullable, Flag, Yes;
import logger = std.experimental.logger;

import cpptooling.analyzer.kind : resolveTypeRef;
import cpptooling.analyzer.type : TypeKindAttr, TypeKind, TypeAttr,
    toStringDecl;
import cpptooling.analyzer.clang.ast : Visitor;
import cpptooling.data.symbol.container : Container;
import cpptooling.data.type : CppAccess;
import cpptooling.utility.unqual : Unqual;

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
        FunctionDecl, Namespace, UnexposedDecl;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeFunctionDecl,
        analyzeVarDecl, analyzeClassDecl, analyzeTranslationUnit;
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

        CppNs[] ns_stack;
    }

    this(ReceiveT recv, Controller ctrl, Parameters params, Products prod, ref Container container) {
        this.recv = recv;
        this.ctrl = ctrl;
        this.params = params;
        this.prod = prod;
        this.container = &container;
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

        if (ns_stack.length == 0) {
            recv.put(result);
        } else {
            recv.put(result, ns_stack);
        }
    }

    override void visit(const(FunctionDecl) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeFunctionDecl(v, *container, indent);

        recv.put(result);
    }

    /** Implicit promise that THIS method will output the class node after the
     * class has been classified.
     */
    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());
        import std.algorithm : map, joiner;

        auto result = analyzeClassDecl(v, *container, indent);

        foreach (loc; container.find!LocationTag(result.type.kind.usr).map!(a => a.any).joiner) {
            //if (!ctrl.doFile(loc.file, loc.file)) {
            //    return;
            //}
        }

        auto visitor = scoped!(UMLClassVisitor!(ReceiveT))(result, ns_stack,
                ctrl, recv, *container, indent + 1);
        v.accept(visitor);

        recv.put(result, ns_stack, visitor.style);
    }

    override void visit(const(Namespace) v) {
        mixin(mixinNodeLog!());

        () @trusted{ ns_stack ~= CppNs(v.cursor.spelling); }();
        // pop the stack when done
        scope (exit)
            ns_stack = ns_stack[0 .. $ - 1];

        // fill the namespace with content from the analyse
        v.accept(this);
    }
}

/**
 *
 * The $(D UMLClassVisitor) do not know when the analyze is finished.
 * Therefore from the viewpoint of $(D UMLClassVisitor) classification is an
 * ongoing process. It is the responsibility of the caller of $(D
 * UMLClassVisitor) to use the final result of the classification together with
 * the style.
 */
private final class UMLClassVisitor(ReceiveT) : Visitor {
    import std.algorithm : map, copy, each, joiner;
    import std.array : Appender;
    import std.conv : to;
    import std.typecons : scoped, TypedefType, NullableRef;

    import cpptooling.analyzer.clang.ast : ClassDecl, CXXBaseSpecifier,
        Constructor, Destructor, CXXMethod, FieldDecl, CXXAccessSpecifier;
    import cpptooling.analyzer.clang.ast.visitor : generateIndentIncrDecr;
    import cpptooling.analyzer.clang.analyze_helper : analyzeClassDecl,
        analyzeConstructor, analyzeDestructor, analyzeCXXMethod,
        analyzeFieldDecl, analyzeCXXBaseSpecified, toAccessType,
        ClassDeclResult;
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
    TypeKindAttr type;

    NodeStyle!UMLClassNode style;

    private {
        Controller ctrl;
        NullableRef!ReceiveT recv;

        Container* container;
        CppNsStack ns_stack;
        CppAccess access;

        /// If the class has any members.
        Flag!"hasMember" hasMember;

        /** Classification of the class.
         * Affected by methods.
         */
        ClassificationState classification;
    }

    this(ref const(ClassDeclResult) result, const(CppNs)[] reside_in_ns,
            Controller ctrl, ref ReceiveT recv, ref Container container, in uint indent) {
        this.ctrl = ctrl;
        this.recv = &recv;
        this.container = &container;
        this.indent = indent;
        this.ns_stack = CppNsStack(reside_in_ns.dup);

        this.access = CppAccess(AccessType.Private);
        this.classification = ClassificationState.Unknown;

        this.type = result.type;
        this.style.label = cast(string) result.name;
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
    override void visit(const(ClassDecl) v) @trusted {
        mixin(mixinNodeLog!());

        //auto result = analyzeClassDecl(v, *container, indent);
        //
        //foreach (loc; container.find!LocationTag(result.type.kind.usr).map!(a => a.any).joiner) {
        //    if (!ctrl.doFile(loc.file, loc.file)) {
        //        return;
        //    }
        //}
        //
        //recv.put(result, ns_stack);
        //
        //auto visitor = scoped!(UMLClassVisitor!(ControllerT, ReceiveT))(result.type,
        //        ns_stack, ctrl, recv, *container, indent + 1);
        //v.accept(visitor);
        //
        //auto result_class = ClassClassificationResult(visitor.type, visitor.classification);
        //recv.put(this.type, result_class);
    }

    /// Analyze the inheritance(s).
    override void visit(const(CXXBaseSpecifier) v) {
        mixin(mixinNodeLog!());
        import cpptooling.analyzer.kind : TypeKind;

        auto result = analyzeCXXBaseSpecified(v, *container, indent);

        recv.put(this.type, result);
    }

    override void visit(const(Constructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeConstructor(v, *container, indent);

        auto tor = CppCtor(result.usr, result.name, result.params, access);
        style.methods ~= access.toInternal!string ~ tor.toString;

        recv.put(this.type, result, access);
    }

    override void visit(const(Destructor) v) {
        mixin(mixinNodeLog!());

        auto result = analyzeDestructor(v, *container, indent);
        updateClassification(MethodKind.Dtor, cast(MemberVirtualType) result.virtualKind);

        auto tor = CppDtor(result.usr, result.name, access, result.virtualKind);
        style.methods ~= access.toInternal!string ~ tor.toString;

        recv.put(this.type, result, access);
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

        recv.put(this.type, result, access);
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

        recv.put(this.type, result, access);
    }

    override void visit(const(CXXAccessSpecifier) v) @trusted {
        import std.conv : to;

        mixin(mixinNodeLog!());
        access = CppAccess(toAccessType(v.cursor.access.accessSpecifier));
    }
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

private enum StereoType {
    None,
    Abstract,
    Interface,
}

private struct ShapeNode {
    string label;

    void toString(Writer)(scope Writer w) const {
        import std.format : formattedWrite;

        formattedWrite(w, `<y:NodeLabel><![CDATA[%s]]></y:NodeLabel>`, label);
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
            node.toString(app);
        }
    }
}

private auto makeShapeNode(string label) {
    return NodeStyle!ShapeNode(ShapeNode(label));
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

    void toString(Writer)(scope Writer w) const {
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
            arg.toString(w);
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

private void xmlNode(RecvT, IdT, UrlT, StyleT)(ref RecvT recv, IdT id, UrlT url, StyleT style) {
    import std.conv : to;
    import std.format : formattedWrite;
    import std.range.primitives : put;

    formattedWrite(recv, `<node id="%s">`, id);

    put(recv, `<data key="d3">`);
    ccdataWrap(recv, url.file);
    put(recv, "</data>");

    put(recv, `<data key="d4">`);
    ccdataWrap(recv, "Line:", url.line.to!string, " Column:", url.column.to!string);
    put(recv, "</data>");

    style.toString(recv);

    put(recv, "</node>\n");
}

private void xmlEdge(RecvT, SourceT, TargetT)(ref RecvT recv, SourceT src, TargetT target) @safe {
    import std.conv : to;
    import std.format : formattedWrite;
    import std.range.primitives : put;

    formattedWrite(recv, `<edge id="e%s" source="%s" target="%s"/>`,
            nextEdgeId.to!string, src, target);
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
 */
class TransformToXmlStream(RecvXmlT, LookupT) if (isOutputRange!(RecvXmlT, char)) {
    import cpptooling.analyzer.clang.analyze_helper : CXXBaseSpecifierResult,
        ClassDeclResult, FieldDeclResult, CXXMethodResult, ConstructorResult,
        DestructorResult, VarDeclResult, FunctionDeclResult,
        TranslationUnitResult;
    import cpptooling.analyzer.type : TypeKindAttr, TypeKind, TypeAttr,
        toStringDecl;
    import cpptooling.data.type : USRType, LocationTag, Location, CppNs;
    import plugin.utility : MarkArray;

    private {
        MarkArray!TypeKindAttr cache_decl;

        RecvXmlT recv;
        bool[USRType] streamed_nodes;
        LookupT lookup;
    }

    this(RecvXmlT recv, LookupT lookup) {
        this.recv = recv;
        this.lookup = lookup;
    }

@safe:

    ///
    void finalize() {
    }

    ///
    void put(ref const(TranslationUnitResult) result) {
        xmlComment(recv, result.fileName);
    }

    /** A free variable declaration.
     *
     * This method do NOT handle those inside a function/method/namespace.
     */
    void put(ref const(VarDeclResult) result) {
        auto file_usr = addFileNode(streamed_nodes, recv, result.location);

        if (result.type.kind.info.kind == TypeKind.Info.Kind.primitive) {
            auto label = result.type.toStringDecl(cast(string) result.name);
            nodeIfMissing(streamed_nodes, recv, result.instanceUSR,
                    makeShapeNode(label), result.location);
            edge(recv, file_usr, result.instanceUSR);
        } else {
            USRType instance_usr;
            Nullable!USRType type_usr;
            addInstanceNode(streamed_nodes, recv, result, lookup, instance_usr, type_usr);

            // connect file to instance
            edge(recv, file_usr, instance_usr);
        }
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

        USRType instance_usr;
        Nullable!USRType type_usr;
        addInstanceNode(streamed_nodes, recv, result, lookup, instance_usr, type_usr);

        // connect ns to instance
        edge(recv, ns_usr, instance_usr);
    }

    ///
    void put(ref const(FunctionDeclResult) result) {
        import cpptooling.data.type : TypeKindVariable, VariadicType;

        auto src = resolveTypeRef(result.type.kind, result.type.attr, lookup).front;
        {
            auto loc = lookup.location(src.kind.usr).front.any;
            nodeIfNotPrimitive(streamed_nodes, recv, src, loc);
        }

        {
            auto target = resolveTypeRef(result.returnType.kind, result.returnType.attr, lookup)
                .front;
            auto loc = lookup.location(target.kind.usr).front.any;
            nodeIfNotPrimitive(streamed_nodes, recv, target, loc);
            edgeIfNotPrimitive(recv, src, target);
        }

        foreach (p; result.params) {
            import std.variant : visit;

            TypeKindAttr type;
            bool is_variadic;

            // dfmt off
            () @trusted {
            p.visit!((const TypeKindVariable v) => type = v.type,
                     (const TypeKindAttr v) => type = v,
                     (const VariadicType v) { is_variadic = true; });
            }();
            // dfmt on

            if (is_variadic) {
                continue;
            }

            auto target = resolveTypeRef(type.kind, type.attr, lookup).front;
            auto loc = lookup.location(target.kind.usr).front.any;
            nodeIfNotPrimitive(streamed_nodes, recv, target, loc);
            edgeIfNotPrimitive(recv, src, target);
        }
    }

    ///
    void put(ref const(ClassDeclResult) result, CppNs[] ns, ref const(NodeStyle!UMLClassNode) style) {
        void putDeclaration(TypeKindAttr type) {
            cache_decl.put(type);
        }

        void putDefinition(TypeKindAttr type, LocationTag loc) {
            nodeIfMissing(streamed_nodes, recv, type.kind.usr, style, loc);
        }

        import std.range : only;

        resolveLocation(&putDeclaration, &putDefinition, only(result.type), lookup);

        auto ns_usr = addNamespaceNode(streamed_nodes, recv, ns);
        if (!ns_usr.isNull) {
            edge(recv, ns_usr, result.type);
        }
    }

    void put(ref const(TypeKindAttr) src, ref const(ConstructorResult) result, in CppAccess access) {
    }

    void put(ref const(TypeKindAttr) src, ref const(DestructorResult) result, in CppAccess access) {
        // do nothing
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXMethodResult) result, in CppAccess access) {
    }

    void put(ref const(TypeKindAttr) src, ref const(FieldDeclResult) result, in CppAccess access) {
        if (result.type.kind.info.kind == TypeKind.Info.Kind.primitive) {
            return;
        }

        LocationTag loc;
        foreach (maybe_loc; lookup.location(result.type.kind.usr).front.any) {
            loc = maybe_loc;
        }

        nodeIfMissing(streamed_nodes, recv, result.type.kind.usr, result.type, loc);

        // connect file to instance
        edge(recv, src.kind.usr, result.type.kind.usr);
    }

    void put(ref const(TypeKindAttr) src, ref const(CXXBaseSpecifierResult) result) {
    }

private:

    import std.range : ElementType;

    /** Resolve a type and store the result in target. */
    static void resolveLocation(TargetDeclT, TargetDefT, Range, LookupT)(
            TargetDeclT target_decl, TargetDefT target_def, Range range, LookupT lookup)
            if (is(Unqual!(ElementType!Range) == TypeKindAttr) && __traits(hasMember,
                LookupT, "kind") && __traits(hasMember, LookupT, "location")) {
        import std.algorithm : map, joiner, cache;
        import std.typecons : tuple;

        // dfmt off
        foreach (ref a; range
                 .map!(a => resolveTypeRef(a.kind, a.attr, lookup))
                 .joiner
                 // a tuple of (TypeKindAttr, DeclLocation)
                 .map!(a => tuple(a, lookup.location(a.kind.usr)))) {
            // no location?
            if (a[1].length == 0) {
                target_decl(a[0]);
                continue;
            }
            auto loc = a[1].front;

            if (loc.hasDefinition) {
                target_def(a[0], loc.definition);
            } else {
                target_decl(a[0]);
            }
        }
        // dfmt on
    }

    // XML support functions

    static Nullable!USRType addNamespaceNode(NodeStoreT, RecvT)(ref NodeStoreT nodes,
            ref RecvT recv, CppNs[] ns) {
        if (ns.length == 0) {
            return Nullable!USRType();
        }

        import cpptooling.data.type : toStringNs;

        auto ns_usr = USRType(ns.toStringNs);

        if (ns_usr !in nodes) {
            auto ns_loc = LocationTag(null);
            nodeIfMissing(nodes, recv, ns_usr, makeShapeNode(cast(string) ns_usr), ns_loc);
        }

        return Nullable!USRType(ns_usr);
    }

    static auto addFileNode(NodeStoreT, RecvT, LocationT)(ref NodeStoreT nodes,
            ref RecvT recv, LocationT location) {
        auto file_usr = cast(USRType) location.file;

        if (file_usr !in nodes) {
            import std.path : baseName;

            auto file_label = location.file.baseName;
            auto file_loc = LocationTag(Location(location.file, 0, 0));

            nodeIfMissing(nodes, recv, file_usr, makeShapeNode(file_label), file_loc);
        }

        return file_usr;
    }

    static void addInstanceNode(NodeStoreT, RecvT, LookupT)(ref NodeStoreT nodes, ref RecvT recv,
            VarDeclResult result, LookupT lookup, out USRType instance_usr,
            out Nullable!USRType type_usr) {
        { // add instance node
            auto label = result.type.toStringDecl(cast(string) result.name);
            nodeIfMissing(nodes, recv, result.instanceUSR, makeShapeNode(label), result.location);
            instance_usr = result.instanceUSR;
        }

        // add node for the type
        auto target = resolveTypeRef(result.type.kind, result.type.attr, lookup).front;
        auto loc = lookup.location(target.kind.usr).front.any;
        nodeIfNotPrimitive(nodes, recv, target, loc);

        // connect instance to type
        if (target.kind.info.kind != TypeKind.Info.Kind.primitive) {
            edge(recv, result.instanceUSR, target);
            type_usr = target.kind.usr;
        }
    }

    static void nodeIfNotPrimitive(NodeStoreT, RecvT, LocationT)(ref NodeStoreT nodes,
            ref RecvT recv, TypeKindAttr type, LocationT loc) {
        if (type.kind.info.kind == TypeKind.Info.Kind.primitive) {
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
    static void nodeIfMissing(NodeStoreT, RecvT, NodeT, LocationT)(ref NodeStoreT nodes,
            ref RecvT recv, USRType node_usr, NodeT node, LocationT loc) {
        if (node_usr in nodes) {
            return;
        }

        import cpptooling.analyzer.type : toStringDecl;

        Location url;
        static if (is(Unqual!LocationT == LocationTag)) {
            url = loc;
        } else {
            if (loc.length != 0) {
                url = loc.front;
            }
        }

        static if (is(Unqual!NodeT == TypeKindAttr)) {
            auto style = makeShapeNode(node.toStringDecl);
        } else {
            auto style = node;
        }

        xmlNode(recv, cast(string) node_usr, url, style);
        nodes[node_usr] = true;
    }

    static void edgeIfNotPrimitive(RecvT)(ref RecvT recv, TypeKindAttr src, TypeKindAttr target) {
        if (target.kind.info.kind == TypeKind.Info.Kind.null_
                || src.kind.info.kind == TypeKind.Info.Kind.primitive
                || target.kind.info.kind == TypeKind.Info.Kind.primitive) {
            return;
        }

        edge(recv, src, target);
    }

    static void edge(RecvT, SrcT, TargetT)(ref RecvT recv, SrcT src, TargetT target) {
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

        xmlEdge(recv, src_usr, target_usr);
    }
}
