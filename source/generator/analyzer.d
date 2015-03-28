/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: MIT License
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
module generator.analyzer;

import std.ascii;
import std.array;
import std.conv;
import std.stdio;
import std.string;
import std.typecons;
import std.experimental.logger;

import tested;

import clang.c.index;
import clang.Cursor;
import clang.Index;
import clang.Token;
import clang.TranslationUnit;
import clang.Visitor;
import clang.UnsavedFile;

import dsrcgen.cpp;

import translator.Type;

version (unittest) {
    shared static this() {
        import std.exception;

        enforce(runUnitTests!(generator.analyzer)(new ConsoleTestResultWriter), "Unit tests failed.");
    }
}

/// Holds the context of the file.
class Context {
    /// Initialize context from file
    this(string input_file) {
        this.input_file = input_file;
        this.index = Index(false, false);

        uint options = 0;

        //uint options = cast(uint) CXTranslationUnit_Flags.CXTranslationUnit_Incomplete | CXTranslationUnit_Flags
        //    .CXTranslationUnit_IncludeBriefCommentsInCodeCompletion | CXTranslationUnit_Flags
        //    .CXTranslationUnit_DetailedPreprocessingRecord;

        this.translation_unit = TranslationUnit.parse(this.index,
            this.input_file, this.args, null, options);
    }

    ~this() {
        translation_unit.dispose;
        index.dispose;
    }

    /// Return: Cursor of the translation unit.
    @property Cursor cursor() {
        return translation_unit.cursor;
    }

private:
    static string[] args = ["-xc++"];
    string input_file;
    Index index;
    TranslationUnit translation_unit;
}

/// No errors occured during translation.
bool isValid(Context context) {
    return context.translation_unit.isValid;
}

/// Print diagnostic error messages.
void diagnostic(Context context) {
    if (!context.isValid())
        return;

    auto dia = context.translation_unit.diagnostics;
    if (dia.length > 0) {
        bool translate = true;
        foreach (diag; dia) {
            auto severity = diag.severity;

            with (CXDiagnosticSeverity)
                if (translate)
                    translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);
            warning(diag.format);
        }
    }
}

/// If apply returns true visit_ast will decend into the node if it contains children.
void visit_ast(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    v.incr();
    bool decend = v.apply(cursor);

    if (!cursor.isEmpty && decend) {
        foreach (child, parent; Visitor(cursor)) {
            visit_ast(child, v);
        }
    }
    v.decr();
}

void log_node(int line = __LINE__, string file = __FILE__,
    string funcName = __FUNCTION__, string prettyFuncName = __PRETTY_FUNCTION__,
    string moduleName = __MODULE__)(ref Cursor c, int level) {
    auto indent_str = new char[level * 2];
    foreach (ref ch; indent_str)
        ch = ' ';

    logf!(line, file, funcName, prettyFuncName, moduleName)(LogLevel.trace,
        "%s|%s [d=%s %s %s line=%d, col=%d %s]", indent_str, c.spelling,
        c.displayName, c.kind, c.type, c.location.spelling.line,
        c.location.spelling.column, c.abilities);
}

/// T is module type.
mixin template VisitNodeModule(Tmodule) {
    alias Entry = Tuple!(Tmodule, "node", int, "level");
    Entry[] stack; // stack of cpp nodes
    int level;

    void incr() {
        level++;
    }

    void decr() {
        // remove node leaving the level
        if (stack.length > 1 && stack[$ - 1].level == level) {
            stack.length = stack.length - 1;
        }
        level--;
    }

    ref Tmodule current() {
        return stack[$ - 1].node;
    }

    T push(T)(T c) {
        stack ~= Entry(cast(Tmodule)(c), level);
        return c;
    }
}
