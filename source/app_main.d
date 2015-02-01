/// Written in the D programming language.
/// @date 2014, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module app_main;
import std.conv;
import std.stdio;
import std.experimental.logger;
alias logger = std.experimental.logger;

import docopt;
import tested;

import clang.c.index;
import clang.Index;
import clang.TranslationUnit;

static string doc = "
usage: autobuilder [options]

options:
 -h, --help     show this
 -d, --debug    turn on debug output for tracing of program flow
";

// Holds the context of the file.
class Context {
    static immutable flags = ["-xc++"];
}

@name("Test a test")
unittest {
    writeln("app_main unit test running");
}

@name("Test creating clang types")
unittest {
    Index index;
    TranslationUnit translationUnit;
    DiagnosticVisitor diagnostics;
}

@name("Test using clang types")
unittest {
    string[] args;
    args ~= "-xc++";

    auto index = Index(false, false);
    auto translationUnit = TranslationUnit.parse(index, "test_files/arrays.h", args);
    scope(exit) translationUnit.dispose;
    scope(exit) index.dispose;

    if (!translationUnit.isValid) {
        writeln("An unknown error occurred");
        //assert(false);
    }

    auto diagnostics = translationUnit.diagnostics;
    if (diagnostics.length > 0) {
	    bool translate = true;
        foreach (diag ; diagnostics)
        {
            auto severity = diag.severity;

            with (CXDiagnosticSeverity)
                if (translate)
                    translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);
            writeln(stderr, diag.format);
        }
    }
}

shared static this() {
    version (unittest) {
        //import core.runtime;
        //Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!app_main(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

int rmain(string[] args) {
    // open file and parse all settings with @option 1|option 2| option 3@
    // print them all to the user
    // go through them and ask user to answer question
    writeln("foo");
    int exit_status = -1;
    bool help = true;
    bool optionsFirst = true;
    auto version_ = "doxygen configuration generator 0.1";

    auto parsed = docopt.docopt(doc, args[1..$], help, version_, optionsFirst);
    if (parsed["--debug"].isTrue) {
        logger.globalLogLevel(LogLevel.all);
    } else {
        logger.globalLogLevel(LogLevel.warning);
    }
    info(to!string(args));
    info(prettyPrintArgs(parsed));

    return exit_status;
}
