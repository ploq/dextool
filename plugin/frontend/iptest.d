module plugin.frontend.iptest;

import logger = std.experimental.logger;

import application.types;
import application.utility;

import plugin.types;

auto runPlugin(CliOption opt, CliArgs args) {
    import docopt;

    auto parsed = docopt.docoptParse(opt, args);

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    return genCpp(cflags);
}

ExitStatusType genCpp(string[] in_cflags) {
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : Yes;
    import std.stdio;

    import cpptooling.analyzer.clang.context : ClangContext;
    import cpptooling.data.representation : CppRoot;

    const auto user_cflags = prependDefaultFlags(in_cflags, "-xc++");

    string[] use_cflags;
    string abs_in_file;

    use_cflags = user_cflags.dup;
    abs_in_file = buildNormalizedPath("functions.h").asAbsolutePath.text;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    write(abs_in_file);
    //if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
    //    return ExitStatusType.Errors;
    //}

    return ExitStatusType.Ok;
}

static auto iptest_opt = CliOptionParts(
       "usage:
 dextool iptest",
    // -------------
    " --in          directory for generated files [default: ./]
",
    // -------------
"others:
 --in=              Input files to parse
"

);
