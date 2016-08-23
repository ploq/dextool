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

struct TestParams {
    Flag!"skipCompare" skipCompare;

    Path root;
    Path input_ext;
    Path base_file_compare;
    Path out_pu;

    // dextool parameters;
    string[] dexParams;
    string[] dexDiagramParams;
    string[] dexFlags;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/graphml").absolutePath;
    p.input_ext = p.root ~ Path(f);
    p.base_file_compare = p.input_ext.stripExtension;

    p.out_pu = testEnv.outdir ~ "graph_raw.xml";

    p.dexParams = ["--DRT-gcopt=profile:1", "graphml", "--debug"];
    p.dexDiagramParams = ["--class-paramdep", "--class-inheritdep", "--class-memberdep"];
    p.dexFlags = [];

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams ~ p.dexDiagramParams, p.dexFlags);

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        Path input = p.base_file_compare;
        // dfmt off
        compareResult(
                      GR(input ~ Ext(".xml.ref"), p.out_pu),
                      );
        // dfmt on
    }
}

// BEGIN Testing #############################################################

@Name(testId ~ "Should be analyse data of a class in global namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("dev/class.hpp", testEnv);
    runTestFile(p, testEnv);
}
