/// Written in the D programming language.
/// @date 2014, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module app_main;
import std.conv;
import std.stdio;
import std.experimental.logger;

import docopt;
import tested;

static string doc = "
usage:
  gen-test-double stub [options] <filename>
  gen-test-double mock [options] <filename>

options:
 -h, --help     show this
 -d, --debug    turn on debug output for tracing of generator flow
";

shared static this() {
    version (unittest) {
        import core.runtime;

        Runtime.moduleUnitTester = () => true;
        //runUnitTests!app(new JsonTestResultWriter("results.json"));
        assert(runUnitTests!app_main(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

int gen_stub() {
    return 0;
}

int rmain(string[] args) {
    int exit_status = -1;
    bool help = true;
    bool optionsFirst = false;
    auto version_ = "gen-test-double v0.1";

    auto parsed = docopt.docopt(doc, args[1 .. $], help, version_, optionsFirst);
    if (parsed["--debug"].isTrue) {
        globalLogLevel(LogLevel.all);
        info(to!string(args));
        info(prettyPrintArgs(parsed));
    }
    else {
        globalLogLevel(LogLevel.warning);
    }

    if (parsed["stub"].isTrue) {
        exit_status = gen_stub();
    }
    else if (parsed["mock"].isTrue) {
        error("Mock generation not implemented yet");
    }
    else {
        error("Usage error");
        writeln(doc);
    }

    return exit_status;
}
