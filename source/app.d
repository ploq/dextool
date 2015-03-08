/// Written in the D programming language.
/// @date 2015, Joakim Brännström
/// @copyright MIT License
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
module app;
import tested;
import std.stdio;

import app_main : rmain;

version (unittest) {
    shared static this() {
        import core.runtime;

        Runtime.moduleUnitTester = () => true;
    }
}

int main(string[] args) {
    version (unittest) {
        writeln(`This application does nothing. Run with "dub build -bunittest"`);
        return 0;
    }
    else {
        return rmain(args);
    }
}
