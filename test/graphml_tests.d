/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module graphml_tests;

import std.typecons : Flag, Yes, No;

import scriptlike;
import unit_threaded : Name, shouldEqual, ShouldFail, shouldBeTrue,
    shouldBeFalse;
import utils;

enum globalTestdir = "graphml_tests";

/** Make a hash out of the raw data.
 *
 * Copied from the implementation
 * import cpptooling.utility.hash : makeHash;
 */
size_t makeHash(T)(T raw) @safe pure nothrow @nogc {
    import std.digest.crc;

    size_t value = 0;

    if (raw is null)
        return value;
    ubyte[4] hash = crc32Of(raw);
    return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
}

struct TestParams {
    Flag!"skipCompare" skipCompare;

    Path root;
    Path input_ext;
    Path out_xml;

    // dextool parameters;
    string[] dexParams;
    string[] dexDiagramParams;
    string[] dexFlags;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/graphml").absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_xml = testEnv.outdir ~ "dextool_raw.graphml";

    p.dexParams = ["--DRT-gcopt=profile:1", "graphml", "--debug"];
    p.dexDiagramParams = ["--class-paramdep", "--class-inheritdep", "--class-memberdep"];
    p.dexFlags = [];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams ~ p.dexDiagramParams, p.dexFlags);
}

auto getDocument(T)(ref T p) {
    import std.xml;

    static import std.file;
    import std.utf : validate;
    import std.xml : Document, check;

    string fin = cast(string) std.file.read(p.out_xml.toString);
    validate(fin);
    check(fin);
    auto xml = new Document(fin);

    return xml;
}

auto getGraph(T)(ref T p) {
    return getDocument(p).elements.filter!(a => a.tag.name == "graph").front;
}

auto getNode(T)(ref T graph, string id) {
    auto id_ = makeHash(id).to!string;
    return graph.elements.filter!(a => a.tag.name == "node" && a.tag.attr["id"].text == id_);
}

auto countNode(T)(ref T graph, string id) {
    return graph.getNode(id).count;
}

auto getEdge(T)(ref T graph, string source, string target) {
    auto src_id = makeHash(source).to!string;
    auto target_id = makeHash(target).to!string;
    return graph.elements.filter!(a => a.tag.name == "edge"
            && a.tag.attr["source"].text == src_id && a.tag.attr["target"].text == target_id);
}

auto countEdge(T)(ref T graph, string source, string target) {
    return graph.getEdge(source, target).map!(a => 1).count;
}

// BEGIN Testing #############################################################

@Name(testId ~ "Should be analyse data of a class in global namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_empty.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be a class in a namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be analyse data of free functions in global namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("functions.h", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);
    string fid = "File:" ~ thisExePath.dirName.toString
        ~ "/testdata/graphml/functions.h Line:44 Column:9$1func_return_func_ptr";

    // test the relation via the return type
    // function exist
    graph.countNode(fid).shouldEqual(1);
    // function relate to return type
    graph.countEdge(fid, "c:functions.h@T@gun_ptr").shouldEqual(1);
}

@Name(
        testId
        ~ "Should be analyze data of free variables in the global namespace related to the file they are declared in")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("variables.h", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    string fid = thisExePath.dirName.toString ~ "/testdata/graphml/variables.h";

    // Nodes for all globals exist.
    graph.countNode("c:@expect_primitive").shouldEqual(1);
    graph.countNode("c:@expect_primitive_array").shouldEqual(1);
    graph.countNode("c:@expect_b").shouldEqual(1);
    graph.countNode("c:@expect_c").shouldEqual(1);
    graph.countNode("c:@expect_d").shouldEqual(1);
    graph.countNode("c:@expect_e").shouldEqual(1);
    graph.countNode("c:@expect_f").shouldEqual(1);
    graph.countNode("c:@expect_g").shouldEqual(1);
    graph.countNode("c:@expect_h").shouldEqual(1);
    graph.countNode("c:@expect_i").shouldEqual(1);
    graph.countNode("c:@expect_my_int").shouldEqual(1);
    graph.countNode("c:@expect_const_my_int").shouldEqual(1);

    // the file should be related to all of them
    graph.countEdge(fid, "c:@expect_primitive").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_primitive_array").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_b").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_c").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_d").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_e").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_f").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_g").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_h").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_i").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_my_int").shouldEqual(1);
    graph.countEdge(fid, "c:@expect_const_my_int").shouldEqual(1);

    // a ptr at a primitive do not result in an edge to the type
    graph.countEdge("c:@expect_d", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:18 Column:13$1expect_d").shouldEqual(0);

    // a ptr at e.g. a typedef of a primitive type result in an edge to the type
    graph.countEdge("c:@expect_const_my_int", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:30 Column:28$1expect_const_my_int").shouldEqual(
            1);
}

@Name(testId ~ "Should be free variables in a namespace and thus related to the namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("variables_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    immutable fid = "ns";

    // Nodes for all globals exist.
    graph.countNode("c:@N@ns@expect_primitive").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_primitive_array").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_b").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_c").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_d").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_e").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_f").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_g").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_h").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_i").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_my_int").shouldEqual(1);
    graph.countNode("c:@N@ns@expect_const_my_int").shouldEqual(1);

    // the file should be related to all of them
    graph.countEdge(fid, "c:@N@ns@expect_primitive").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_primitive_array").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_b").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_c").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_d").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_e").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_f").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_g").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_h").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_i").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_my_int").shouldEqual(1);
    graph.countEdge(fid, "c:@N@ns@expect_const_my_int").shouldEqual(1);

    // a ptr at a primitive do not result in an edge to the type
    graph.countEdge("c:@N@ns@expect_d", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:18 Column:13$1expect_d").shouldEqual(0);

    // a ptr at e.g. a typedef of a primitive type result in an edge to the type
    graph.countEdge("c:@N@ns@expect_const_my_int", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/variables.h Line:30 Column:28$1expect_const_my_int").shouldEqual(
            1);
}

@Name(testId ~ "Should be all type of class classifications")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_variants_interface.hpp", testEnv);
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be all kind of member relations between classes")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_members.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // test forward declarations
    graph.countNode("c:@S@ToForward").shouldEqual(1);
    graph.countNode("c:@S@Forward_ptr").shouldEqual(1);
    graph.countNode("c:@S@Forward_ref").shouldEqual(1);
    graph.countNode("c:@S@Forward_decl").shouldEqual(1);
    graph.countEdge("c:@S@ToForward", "c:@S@Forward_ptr").shouldEqual(1);
    graph.countEdge("c:@S@ToForward", "c:@S@Forward_ref").shouldEqual(1);
    graph.countEdge("c:@S@ToForward", "c:@S@Forward_decl").shouldEqual(1);

    // test definitions
    graph.countNode("c:@S@Impl").shouldEqual(1);
    graph.countNode("c:@S@Impl_ptr").shouldEqual(1);
    graph.countNode("c:@S@Impl_ref").shouldEqual(1);
    graph.countNode("c:@S@ToImpl").shouldEqual(1);
    graph.countEdge("c:@S@ToImpl", "c:@S@Impl").shouldEqual(1);
    graph.countEdge("c:@S@ToImpl", "c:@S@Impl_ref").shouldEqual(1);
    graph.countEdge("c:@S@ToImpl", "c:@S@Impl_ptr").shouldEqual(1);

    // test that an edge to a primitive type is not formed
    graph.countNode("c:@S@ToPrimitive").shouldEqual(1);
    // dfmt off
    graph.elements
        // all edges from the node
        .filter!(a => a.tag.name == "edge" && a.tag.attr["source"].text == makeHash("c:@S@ToPrimitive").to!string())
        .count
        .shouldEqual(0);
    // dfmt on

    // test that a node and edge to a funcptr is formed
    graph.countNode("File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/class_members.hpp Line:43 Column:12$1__foo").shouldEqual(1);
    graph.countEdge("c:@S@ToFuncPtr", "File:" ~ thisExePath.dirName.toString
            ~ "/testdata/graphml/class_members.hpp Line:43 Column:12$1__foo").shouldEqual(1);
}

@Name(testId ~ "Should be a inheritance representation")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_inherit.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // test inherit depth of 2
    // VirtC -> VirtB -> VirtA
    graph.countNode("c:@S@VirtA").shouldEqual(1);
    graph.countNode("c:@S@VirtB").shouldEqual(1);
    graph.countNode("c:@S@VirtC").shouldEqual(1);

    graph.countEdge("c:@S@VirtB", "c:@S@VirtA").shouldEqual(1);
    graph.countEdge("c:@S@VirtC", "c:@S@VirtB").shouldEqual(1);

    // test multiple inheritance
    // Dup inherit from DupA and DupB
    graph.countNode("c:@S@Dup").shouldEqual(1);
    graph.countNode("c:@S@DupA").shouldEqual(1);
    graph.countNode("c:@S@DupB").shouldEqual(1);

    graph.countEdge("c:@S@Dup", "c:@S@DupA").shouldEqual(1);
    graph.countEdge("c:@S@Dup", "c:@S@DupB").shouldEqual(1);
}

@Name(testId ~ "Should be a class with methods represented and relations to method parameters")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("class_methods.hpp", testEnv);
    runTestFile(p, testEnv);

    auto graph = getGraph(p);

    // test that usage of a type in a method parameter result in a relation
    graph.countEdge("c:@S@Methods", "c:class_methods.hpp@T@MadeUp").shouldEqual(1);
    graph.countEdge("c:@S@Virtual", "c:class_methods.hpp@T@MadeUp").shouldEqual(1);
}
