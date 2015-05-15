/// Written in the D programming language.
/// Date: 2014-2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module app_main;

import std.conv;
import std.exception;
import std.stdio;
import std.string;
import std.typecons;

import file = std.file;
import logger = std.experimental.logger;

import docopt;
import argvalue; // from docopt
import tested;
import dsrcgen.cpp;

static string doc = "
usage:
  gen-test-double stub [options] FILE [--] [CFLAGS...]
  gen-test-double mock [options] FILE

arguments:
 FILE           C++ header to generate stubs from
 CFLAGS         Compiler flags.

options:
 -h, --help     show this
 -d=<dest>      destination of generated files [default: .]
 --debug        turn on debug output for tracing of generator flow
 --limit=<l>    limit generation to input FILE or process everything [default: single]
                Can be single or all.
";

enum ExitStatusType {
    Ok,
    Errors
}

enum GeneratorLimitType {
    Invalid,
    All,
    Single
}

auto stringToGeneratorLimitType(string s) {
    switch (s) {
    case "all":
        return GeneratorLimitType.All;
    case "single":
        return GeneratorLimitType.Single;
    default:
        return GeneratorLimitType.Invalid;
    }
}

class SimpleLogger : logger.Logger {
    int line = -1;
    string file = null;
    string func = null;
    string prettyFunc = null;
    string msg = null;
    logger.LogLevel lvl;

    this(const logger.LogLevel lv = logger.LogLevel.info) {
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

auto try_open_file(string filename, string mode) @trusted nothrow {
    Unique!File rval;
    try {
        rval = Unique!File(new File(filename, mode));
    }
    catch (Exception ex) {
    }
    if (rval.isEmpty) {
        try {
            logger.errorf("Unable to read/write file '%s'", filename);
        }
        catch (Exception ex) {
        }
    }

    return rval;
}

ExitStatusType gen_stub(const string infile, const string outdir,
    const ref string[] cflags, GeneratorLimitType limit) {
    import std.exception;
    import std.path : baseName, buildPath, stripExtension;
    import generator;

    auto hdr_ext = ".hpp";
    auto impl_ext = ".cpp";
    auto prefix = StubPrefix("Stub");

    auto base_filename = infile.baseName.stripExtension;
    HdrFilename hdr_filename = HdrFilename(base_filename ~ hdr_ext);
    HdrFilename stub_hdr_filename = HdrFilename((cast(string) prefix).toLower ~ "_" ~ hdr_filename);
    string hdr_out_filename = buildPath(outdir, cast(string) stub_hdr_filename);
    string impl_out_filename = buildPath(outdir,
        (cast(string) prefix).toLower ~ "_" ~ base_filename ~ impl_ext);

    if (!file.exists(infile)) {
        logger.errorf("File '%s' do not exist", infile);
        return ExitStatusType.Errors;
    }

    logger.infof("Generating stub from '%s'", infile);

    auto file_ctx = new Context(infile, cflags);
    file_ctx.logDiagnostic;
    if (file_ctx.hasParseErrors)
        return ExitStatusType.Errors;

    auto ctx = new StubContext(prefix, HdrFilename(infile.baseName));
    if (limit == GeneratorLimitType.Single)
        ctx.onlyTranslateFile(HdrFilename(infile));
    ctx.translate(file_ctx.cursor);

    auto outfile_hdr = try_open_file(hdr_out_filename, "w");
    if (outfile_hdr.isEmpty) {
        return ExitStatusType.Errors;
    }
    scope (exit)
        outfile_hdr.close();

    auto outfile_impl = try_open_file(impl_out_filename, "w");
    if (outfile_impl.isEmpty) {
        return ExitStatusType.Errors;
    }
    scope (exit)
        outfile_impl.close();

    try {
        outfile_hdr.write(ctx.output_header(stub_hdr_filename));
        outfile_impl.write(ctx.output_impl(stub_hdr_filename));
    }
    catch (ErrnoException ex) {
        logger.trace(text(ex));
        return ExitStatusType.Errors;
    }

    return ExitStatusType.Ok;
}

void prepare_env(ref ArgValue[string] parsed) {
    import std.experimental.logger.core : sharedLog;

    try {
        if (parsed["--debug"].isTrue) {
            logger.globalLogLevel(logger.LogLevel.all);
        }
        else {
            logger.globalLogLevel(logger.LogLevel.info);
            auto simple_logger = new SimpleLogger();
            logger.sharedLog(simple_logger);
        }
    }
    catch (Exception ex) {
        collectException(logger.error("Failed to configure logging level"));
        throw ex;
    }
}

ExitStatusType do_test_double(ref ArgValue[string] parsed) {
    import std.algorithm : among;

    ExitStatusType exit_status = ExitStatusType.Errors;
    GeneratorLimitType limit = stringToGeneratorLimitType(parsed["--limit"].toString);

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    if (limit == GeneratorLimitType.Invalid) {
        logger.error("Usage error: --limit must be either all or single");
        writeln(doc);
    }
    else if (parsed["stub"].isTrue) {
        exit_status = gen_stub(parsed["FILE"].toString, parsed["-d"].toString, cflags,
            limit);
    }
    else if (parsed["mock"].isTrue) {
        logger.error("Mock generation not implemented yet");
    }
    else {
        logger.error("Usage error");
        writeln(doc);
    }

    return exit_status;
}

int rmain(string[] args) nothrow {
    import std.array : join;

    string errmsg, tracemsg;
    ExitStatusType exit_status = ExitStatusType.Errors;
    bool help = true;
    bool optionsFirst = false;
    auto version_ = "gen-test-double v0.1";

    try {
        auto parsed = docopt.docopt(doc, args[1 .. $], help, version_, optionsFirst);
        prepare_env(parsed);
        logger.trace(to!string(args));
        logger.trace(join(args, " "));
        logger.trace(prettyPrintArgs(parsed));

        exit_status = do_test_double(parsed);
    }
    catch (Exception ex) {
        collectException(logger.trace(text(ex)));
        exit_status = ExitStatusType.Errors;
    }

    return cast(typeof(return)) exit_status;
}
