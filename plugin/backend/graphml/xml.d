/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module plugin.backend.graphml.xml;

import std.format : FormatSpec;
import logger = std.experimental.logger;

import cpptooling.utility.hash : makeHash;

version (unittest) {
    import unit_threaded : shouldEqual;
}

private ulong nextEdgeId()() {
    static ulong next = 0;
    return next++;
}

/// Write the XML header for graphml with needed key definitions.
void xmlHeader(RecvT)(ref RecvT recv) {
    import std.conv : to;
    import std.format : formattedWrite;
    import std.range.primitives : put;

    put(recv, `<?xml version="1.0" encoding="UTF-8"?>` ~ "\n");
    put(recv, `<graphml` ~ "\n");
    put(recv, ` xmlns="http://graphml.graphdrawing.org/xmlns"` ~ "\n");
    put(recv, ` xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"` ~ "\n");
    put(recv, ` xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns` ~ "\n");
    put(recv, `   http://www.yworks.com/xml/schema/graphml/1.1/ygraphml.xsd"` ~ "\n");
    put(recv, ` xmlns:y="http://www.yworks.com/xml/graphml">` ~ "\n");

    put(recv, `<graph id="G" edgedefault="directed">` ~ "\n");

    formattedWrite(recv,
            `<key for="node" attr.name="url" attr.type="string" id="d%s"/>` ~ "\n",
            cast(int) IdT.url);
    formattedWrite(recv, `<key for="node" attr.name="description" attr.type="string" id="d%s"/>` ~ "\n",
            cast(int) IdT.description);
    formattedWrite(recv, `<key for="node" attr.name="kind" attr.type="string" id="d%s"/>` ~ "\n",
            cast(int) IdT.kind);
    formattedWrite(recv, `<key for="node" attr.name="typeAttr" attr.type="string" id="d%s"/>` ~ "\n",
            cast(int) IdT.typeAttr);
    formattedWrite(recv, `<key for="node" attr.name="signature" attr.type="string" id="d%s"/>` ~ "\n",
            cast(int) IdT.signature);
    formattedWrite(recv, `<key for="edge" yfiles.type="nodegraphics" id="d%s"/>` ~ "\n",
            cast(int) IdT.nodegraphics);
    formattedWrite(recv, `<key for="node" yfiles.type="edgegraphics" id="d%s"/>` ~ "\n",
            cast(int) IdT.edgegraphics);
}

@("Should be enum IDs converted to int strings")
unittest {
    // Even though the test seems stupid it exists to ensure that the first and
    // last ID is as expected. If they mismatch then the header generator is
    // probably wrong.
    import std.format : format;

    format("%s", cast(int) IdT.url).shouldEqual("3");
    format("%s", cast(int) IdT.edgegraphics).shouldEqual("9");
}

/// Write the xml footer as required by GraphML.
void xmlFooter(RecvT)(ref RecvT recv) {
    import std.range.primitives : put;

    put(recv, "</graph>\n");
    put(recv, "</graphml>\n");
}

package enum ColorKind {
    none,
    file,
    global,
    globalConst,
    globalStatic,
    namespace,
    func,
    class_
}

package @safe struct ValidNodeId {
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

package enum StereoType {
    None,
    Abstract,
    Interface,
}

package struct ShapeNode {
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

package struct UMLClassNode {
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

@("Should instantiate all NodeStyles")
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

package auto makeShapeNode(string label, ColorKind color = ColorKind.none) {
    return NodeStyle!ShapeNode(ShapeNode(label, color));
}

package auto makeUMLClassNode(string label) {
    return NodeStyle!UMLClassNode(UMLClassNode(label));
}

/** Node style in GraphML.
 *
 * Intented to carry metadata and formatting besides a generic label.
 */
package struct NodeStyle(PayloadT) {
    import std.format : formattedWrite;

    PayloadT payload;
    alias payload this;

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char spec) const {
        import std.range.primitives : put;

        enum graph_node = PayloadT.stringof;

        put(w, `<data key="d5">`);
        formattedWrite(w, "<y:%s>%s</y:%s>", graph_node, payload, graph_node);
        put(w, "</data>");
    }
}

package void ccdataWrap(Writer, ARGS...)(scope Writer w, auto ref ARGS args) {
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

package void xmlComment(RecvT, CharT)(ref RecvT recv, CharT v) {
    import std.format : formattedWrite;

    formattedWrite(recv, "<!-- %s -->\n", v);
}

package struct XmlNode(UrlT, StyleT) {
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

package enum IdT {
    dummy0,
    dummy1,
    dummy2,
    url,
    description,
    kind,
    typeAttr,
    signature,
    nodegraphics,
    edgegraphics,
}

package struct Attr {
    IdT id;
}

/// Stream to put attribute data into for complex member methods that handle
/// the serialization themself.
package alias StreamChar = void delegate(const(char)[]);

/** Serialize a struct into the writer.
 *
 * Only those fields and functions tagged with the UDA Attr are serialized into
 * xml elements.
 * The "id" as required by GraphML for custom data is derived from Attr.
 *
 * Params:
 *  RecvT = an OutputRange of char
 *  T = type to analyse for UDA's
 *  recv = ?
 *  bundle = ?
 */
package void attrToXml(T, Writer)(ref T bundle, scope Writer recv) {
    import std.conv : to;
    import std.format : formattedWrite;
    import std.range.primitives : put;
    import std.traits;
    import std.meta;

    static void dataTag(Writer, T)(scope Writer recv, Attr attr, T data) {
        formattedWrite(recv, `<data key="d%s">`, cast(int) attr.id);

        static if (isSomeFunction!T) {
            data((scope const(char)[] buf) { put(recv, buf); });
        } else static if (__traits(hasMember, T, "get")) {
            // for Nullable etc
            ccdataWrap(recv, data.get);
        } else {
            ccdataWrap(recv, data);
        }

        put(recv, "</data>");
    }

    // TODO block when trying to stream multiple key's with same id

    foreach (member_name; __traits(allMembers, T)) {
        alias memberType = Alias!(__traits(getMember, T, member_name));
        alias res = getUDAs!(memberType, Attr);
        // lazy helper for retrieving the compose `bundle.<field>`
        enum member = "__traits(getMember, bundle, member_name)";

        static if (res.length == 0) {
            // ignore those without the UDA Attr
        } else static if (isSomeFunction!memberType) {
            // process functions
            // may only have one parameter and it must accept the delegate StreamChar
            static if (std.traits.Parameters!(memberType).length == 1
                    && is(std.traits.Parameters!(memberType)[0] == StreamChar)) {
                dataTag(recv, res[0], &mixin(member));
            } else {
                static assert(0,
                        "member function tagged with Attr may only take one argument. The argument must be of type "
                        ~ typeof(StreamChar).stringof ~ " but is of type " ~ std.traits.Parameters!(memberType)
                        .stringof);
            }
        } else static if (is(typeof(memberType.init))) {
            // process basic types
            dataTag(recv, res[0], mixin(member));
        }
    }
}

@("Should serialize those fields and methods of the struct that has the UDA Attr")
unittest {
    static struct Foo {
        int ignore;
        @Attr(IdT.kind) string value;
        @Attr(IdT.url) void f(StreamChar stream) {
            stream("f");
        }
    }

    char[] buf;
    struct Recv {
        void put(const(char)[] s) {
            buf ~= s;
        }
    }

    Recv recv;
    auto s = Foo(1, "value_");
    attrToXml(s, recv);
    (cast(string) buf).shouldEqual(
            `<data key="d5"><![CDATA[value_]]></data><data key="d3">f</data>`);
}

package enum NodeId;
package enum NodeExtra;

package void nodeToXml(T, Writer)(ref T bundle, scope Writer recv) {
    import std.format : formattedWrite;
    import std.range.primitives : put;
    import std.traits;
    import std.meta;

    // lazy helper for retrieving the compose `bundle.<field>`
    enum member = "__traits(getMember, bundle, member_name)";

    put(recv, "<node ");
    scope (success)
        put(recv, "</node>\n");

    // ID
    foreach (member_name; __traits(allMembers, T)) {
        alias memberType = Alias!(__traits(getMember, T, member_name));
        alias res = getUDAs!(memberType, NodeId);

        static if (res.length == 0) {
            // ignore those without the UDA Attr
        } else {
            formattedWrite(recv, `id="%s"`, mixin(member));
        }
    }
    put(recv, ">");

    attrToXml(bundle, recv);

    // Extra
    foreach (member_name; __traits(allMembers, T)) {
        alias memberType = Alias!(__traits(getMember, T, member_name));
        alias res = getUDAs!(memberType, NodeExtra);

        static if (res.length == 0) {
            // ignore those without the UDA Attr
        } else static if (isSomeFunction!memberType) {
            mixin(member)((scope const(char)[] buf) { put(recv, buf); });
        } else {
            static if (isSomeString!(typeof(memberType))) {
                ccdataWrap(recv, mixin(member));
            } else {
                import std.conv : to;

                ccdataWrap(recv, mixin(member).to!string());
            }
        }
    }
}

@("Should serialize a node by the UDA's")
unittest {
    static struct Foo {
        @NodeId int id;
        @Attr(IdT.description) string desc;

        @NodeExtra void extra(StreamChar s) {
            s("extra");
        }
    }

    char[] buf;
    struct Recv {
        void put(const(char)[] s) {
            buf ~= s;
        }
    }

    Recv recv;
    auto s = Foo(3, "desc");
    nodeToXml(s, recv);
    (cast(string) buf).shouldEqual(
            `<node id="3"><data key="d4"><![CDATA[desc]]></data>extra</node>
`);
}

package enum EdgeKind {
    Directed,
    Generalization
}

package void xmlEdge(RecvT, SourceT, TargetT)(ref RecvT recv, SourceT src,
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
