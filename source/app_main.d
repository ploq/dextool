/// Written in the D programming language.
/// @date 2014, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module app_main;

import std.ascii;
import std.conv;
import std.file;
import std.stdio;
import std.string;
import std.experimental.logger;

import docopt;
import tested;

class SimpleLogger : Logger {
    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    LogLevel lvl;

    this(const LogLevel lv = LogLevel.info) {
        super(lv);
    }

    override void writeLogMsg(ref LogEntry payload) {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        writef("%s: %s%s", text(this.lvl), this.msg, newline);
    }
}

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

int gen_stub(string filename) {
    import analyzer;

    if (!exists(filename)) {
        errorf("File '%s' do not exist", filename);
        return -1;
    }

    writefln("Generating stub from file '%s'", filename);

    auto ctx = new Context(filename);
    ctx.diagnostic();

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
        auto simple_logger = new SimpleLogger();
        stdlog = simple_logger;
    }

    if (parsed["stub"].isTrue) {
        exit_status = gen_stub(parsed["<filename>"].toString);
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
