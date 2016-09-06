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

    p.out_pu = testEnv.outdir ~ "dextoo_raw.graphml";

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
                      GR(input ~ Ext(".graphml.ref"), p.out_pu),
                      );
        // dfmt on
    }
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
}

@Name(
        testId
        ~ "Should be analyze data of free variables in the global namespace related to the file they are declared in")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("variables.h", testEnv);
    runTestFile(p, testEnv);
}

@Name(testId ~ "Should be free variables in a namespace and thus related to the namespace")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("variables_in_ns.hpp", testEnv);
    runTestFile(p, testEnv);
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
}
