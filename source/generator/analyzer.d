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
    /** Initialize context from file
     * Params:
     *  input_file = filename of code to parse
     */
    this(string input_file) {
        this.input_file = input_file;
        this.index = Index(false, false);

        // the last argument determines if comments are parsed and therefor
        // accessible in the AST
        this.translation_unit = TranslationUnit.parse(this.index,
            this.input_file, this.args);
    }

    ~this() {
        translation_unit.dispose;
        index.dispose;
    }

    /** Top cursor to travers the AST.
     * Return: Cursor of the translation unit
     */
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

/** Query context for if diagnostic errors where detected during parsing.
 * Return: True if errors where found.
 */
bool has_parse_errors(Context context) {
    auto dia = context.translation_unit.diagnostics;
    return dia.length > 0;
}

/// Log diagnostic error messages to std.logger.
void log_diagnostic(Context context) {
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

/** Visit all nodes in a Clang AST to call apply on the nodes.
 * The functions incr() and decr() are infered at compile time.
 * The function incr() is called when entering a new level in the AST and decr() is called when leaving.
 * The return value from apply() determines if visit_ast will decend into that node.
 *
 * Params:
 *  cursor = Top cursor to traverse from.
 *  v = User context to apply on the nodes in the AST.
 * Example:
 * ---
 * visit_ast!TranslateContext(cursor, this);
 * ---
 */
void visit_ast(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    import std.traits;
    static if (__traits(hasMember, VisitorType, "incr")) {
        v.incr();
    }
    bool decend = v.apply(cursor);

    if (!cursor.isEmpty && decend) {
        foreach (child, parent; Visitor(cursor)) {
            visit_ast(child, v);
        }
    }

    static if (__traits(hasMember, VisitorType, "decr")) {
        v.decr();
    }
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
/** Stack useful when visiting the AST.
 * Could be used to know what node to attach code in.
 * Params:
 *  Tmodule = object type to build the stack of
 * Example:
 * ---
 * mixin VisitNodeModule!CppModule;
 * CppModule node;
 * push(node);
 * current.sep();
 * ---
 */
struct VisitNodeModule(Tmodule) {
    alias Entry = Tuple!(Tmodule, "node", int, "level");
    private Entry[] stack; // stack of cpp nodes
    private int level;

public:
    /// Increment the AST depth.
    void incr() {
        level++;
    }

    /// Pop the stack if depth matches depth of top element of stack.
    void decr() {
        // remove node when leavin the matching level
        if (stack.length > 1 && stack[$ - 1].level == level) {
            stack.length = stack.length - 1;
        }
        level--;
    }

    /// Return: AST depth when traversing.
    @property auto depth() {
        return level;
    }

    /// Return: Top of the stack.
    @property ref Tmodule current() {
        return stack[$ - 1].node;
    }

    /** Push an element to the stack together with current AST depth.
     * Params:
     *  c = Element to push
     *
     * Return: Pushed element.
     */
    T push(T)(T c) {
        stack ~= Entry(cast(Tmodule)(c), level);
        return c;
    }
}
