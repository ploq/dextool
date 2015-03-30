/// Written in the D programming language.
/// @date 2014, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module app_main;

import std.conv;
import std.exception;
import std.file;
import std.stdio;
import std.string;
import std.experimental.logger;

import docopt;
import argvalue; // from docopt
import tested;
import dsrcgen.cpp;

static string doc = "
usage:
  gen-test-double stub [options] <infile> <outfile>
  gen-test-double mock [options] <infile> <outfile>

options:
 -h, --help     show this
 -d, --debug    turn on debug output for tracing of generator flow
";

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

    override void writeLogMsg(ref LogEntry payload) @trusted {
        this.line = payload.line;
        this.file = payload.file;
        this.func = payload.funcName;
        this.prettyFunc = payload.prettyFuncName;
        this.lvl = payload.logLevel;
        this.msg = payload.msg;

        stderr.writefln("%s: %s", text(this.lvl), this.msg);
    }
}

shared static this() {
    version (unittest) {
        import core.runtime;

        Runtime.moduleUnitTester = () => true;
        assert(runUnitTests!app_main(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

int gen_stub(in string infile, in string outfile) {
    import std.exception;
    import generator;

    if (!exists(infile)) {
        errorf("File '%s' do not exist", infile);
        return -1;
    }

    infof("Generating stub from file '%s'", infile);

    auto file_ctx = new Context(infile);
    file_ctx.log_diagnostic();

    auto ctx = new StubContext;
    ctx.translate(file_ctx.cursor);

    try {
        auto open_outfile = File(outfile, "w");
        scope(exit) open_outfile.close();
        open_outfile.write(ctx.render_header);
    }
    catch (ErrnoException ex) {
        trace(text(ex));
        errorf("Unable to write to file '%s'", outfile);
        return -1;
    }

    return 0;
}

void prepare_env(ref ArgValue[string] parsed) {
    import std.experimental.logger.core : sharedLog;

    try {
        if (parsed["--debug"].isTrue) {
            globalLogLevel(LogLevel.all);
        }
        else {
            globalLogLevel(LogLevel.info);
            auto simple_logger = new SimpleLogger();
            sharedLog(simple_logger);
        }
    }
    catch (Exception ex) {
        collectException(error("Failed to configure logging level"));
        throw ex;
    }
}

int do_test_double(ref ArgValue[string] parsed) {
    int exit_status = -1;

    if (parsed["stub"].isTrue) {
        exit_status = gen_stub(parsed["<infile>"].toString, parsed["<outfile>"].toString);
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

int rmain(string[] args) nothrow {
    string errmsg, tracemsg;
    int exit_status = -1;
    bool help = true;
    bool optionsFirst = false;
    auto version_ = "gen-test-double v0.1";

    try {
        auto parsed = docopt.docopt(doc, args[1 .. $], help, version_, optionsFirst);
        prepare_env(parsed);
        trace(to!string(args));
        trace(prettyPrintArgs(parsed));

        exit_status = do_test_double(parsed);
    }
    catch (Exception ex) {
        collectException(trace(text(ex)));
        exit_status = -1;
    }

    return exit_status;
}
