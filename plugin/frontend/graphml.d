/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Analyze C/C++ source code to generate a GraphML of the relations.
*/
module plugin.frontend.graphml;

import std.typecons : Flag;

import logger = std.experimental.logger;

import application.compilation_db;
import application.types;
import application.utility;

import plugin.types;
import plugin.backend.graphml : Controller, Parameters, Products;

auto runPlugin(CliBasicOption opt, CliArgs args) {
    import std.typecons : TypedefType;
    import docopt;

    auto parsed = docopt.docoptParse(opt.toDocopt(graphml_opt), args);

    string[] cflags;
    if (parsed["--"].isTrue) {
        cflags = parsed["CFLAGS"].asList;
    }

    import plugin.docopt_util;

    printArgs(parsed);

    auto variant = GraphMLFrontend.makeVariant(parsed);

    CompileCommandDB compile_db;
    if (!parsed["--compile-db"].isEmpty) {
        compile_db = parsed["--compile-db"].asList.fromArgCompileDb;
    }

    auto skipFileError = cast(Flag!"skipFileError") parsed["--skip-file-error"].isTrue;

    return pluginMain(variant, cflags, compile_db, InFiles(parsed["--in"].asList), skipFileError);
}

// dfmt off
static auto graphml_opt = CliOptionParts(
    "usage:
 dextool graphml [options] [--compile-db=...] [--file-exclude=...] [--in=...] [--] [CFLAGS...]
 dextool graphml [options] [--compile-db=...] [--file-restrict=...] [--in=...] [--] [CFLAGS...]",
    // -------------
    " --out=dir           directory for generated files [default: ./]
 --file-prefix=p     Prefix used for generated files [default: graph_]
 --class-method      Analyse class methods
 --class-paramdep    Analyse class method parameters
 --class-inheritdep  Analyse class inheritance
 --class-memberdep   Analyse class member
 --skip-file-error   Skip files that result in compile errors (only when using compile-db and processing all files)",
    // -------------
"others:
 --in=              Input files to parse
 --compile-db=j      Retrieve compilation parameters from the file
 --file-exclude=     Exclude files from generation matching the regex
 --file-restrict=    Restrict the scope of the test double to those files
                     matching the regex
"
);
// dfmt on

class GraphMLFrontend : Controller, Parameters, Products {
    import std.regex : regex, Regex;
    import application.types : FileName, DirName;
    import docopt : ArgValue;

    private {
        static struct FileData {
            FileName filename;
            string data;
        }

        immutable Flag!"genClassMethod" gen_class_method;
        immutable Flag!"genClassParamDependency" gen_class_param_dep;
        immutable Flag!"genClassInheritDependency" gen_class_inherit_dep;
        immutable Flag!"genClassMemberDependency" gen_class_member_dep;

        immutable FilePrefix file_prefix;
        immutable DirName output_dir;

        Regex!char[] exclude;
        Regex!char[] restrict;
    }

    /// Data produced by the generatore intented to be written to specified file.
    FileData[] fileData;

    static auto makeVariant(ref ArgValue[string] parsed) {
        import std.algorithm : map;
        import std.array : array;

        Regex!char[] exclude = parsed["--file-exclude"].asList.map!(a => regex(a)).array();
        Regex!char[] restrict = parsed["--file-restrict"].asList.map!(a => regex(a)).array();

        auto gen_class_method = cast(Flag!"genClassMethod") parsed["--class-method"].isTrue;
        auto gen_class_param_dep = cast(Flag!"genClassParamDependency") parsed["--class-paramdep"]
            .isTrue;
        auto gen_class_inherit_dep = cast(Flag!"genClassInheritDependency") parsed[
        "--class-inheritdep"].isTrue;
        auto gen_class_member_dep = cast(Flag!"genClassMemberDependency") parsed[
        "--class-memberdep"].isTrue;

        auto variant = new GraphMLFrontend(FilePrefix(parsed["--file-prefix"].toString),
                DirName(parsed["--out"].toString),
                gen_class_method, gen_class_param_dep, gen_class_inherit_dep,
                gen_class_member_dep);

        variant.exclude = exclude;
        variant.restrict = restrict;

        return variant;
    }

    this(FilePrefix file_prefix, DirName output_dir, Flag!"genClassMethod" class_method,
            Flag!"genClassParamDependency" class_param_dep,
            Flag!"genClassInheritDependency" class_inherit_dep,
            Flag!"genClassMemberDependency" class_member_dep) {

        this.file_prefix = file_prefix;
        this.output_dir = output_dir;
        this.gen_class_method = class_method;
        this.gen_class_param_dep = class_param_dep;
        this.gen_class_inherit_dep = class_inherit_dep;
        this.gen_class_member_dep = class_member_dep;
    }
}

ExitStatusType pluginMain(GraphMLFrontend variant, in string[] in_cflags,
        CompileCommandDB compile_db, InFiles in_files, Flag!"skipFileError" skipFileError) {
    import std.conv : text;
    import std.path : buildNormalizedPath, asAbsolutePath;
    import std.typecons : TypedefType, Yes;

    import cpptooling.analyzer.clang.context : ClangContext;
    import plugin.backend.graphml : GraphMLAnalyzer;

    const auto user_cflags = prependDefaultFlags(in_cflags, "-xc");
    const auto total_files = in_files.length;
    auto visitor = new GraphMLAnalyzer(variant, variant, variant);
    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);

    foreach (idx, in_file; (cast(TypedefType!InFiles) in_files)) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        string[] use_cflags;
        string abs_in_file;

        // TODO duplicate code in c, c++ and plantuml. Fix it.
        if (compile_db.length > 0) {
            auto db_search_result = compile_db.appendOrError(user_cflags, in_file);
            if (db_search_result.isNull) {
                return ExitStatusType.Errors;
            }
            use_cflags = db_search_result.get.cflags;
            abs_in_file = db_search_result.get.absoluteFile;
        } else {
            use_cflags = user_cflags.dup;
            abs_in_file = buildNormalizedPath(in_file).asAbsolutePath.text;
        }

        if (analyzeFile(abs_in_file, use_cflags, visitor, ctx) == ExitStatusType.Errors) {
            return ExitStatusType.Errors;
        }
    }

    debug {
        logger.trace(visitor);
    }

    return writeFileData(variant.fileData);
}
