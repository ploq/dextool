/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
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
module cpptooling.data.representation;

import std.array : Appender;
import std.range : isInputRange;
import std.typecons : Typedef, Tuple, Flag;
import std.variant : Algebraic;
import logger = std.experimental.logger;
import std.experimental.testing : name;

import translator.Type : TypeKind, makeTypeKind, duplicate;
import cpptooling.utility.range : arrayRange;
import cpptooling.utility.conv : str;

version (unittest) {
    import test.helpers : shouldEqualPretty;
    import std.experimental.testing : shouldEqual, shouldBeGreaterThan;
}

public:

/// Name of a C++ namespace.
alias CppNs = Typedef!(string, string.init, "CppNs");
/// Stack of nested C++ namespaces.
alias CppNsStack = CppNs[];
/// Nesting of C++ namespaces as a string.
alias CppNsNesting = Typedef!(string, string.init, "CppNsNesting");

alias CppVariable = Typedef!(string, string.init, "CppVariable");
alias TypeKindVariable = Tuple!(TypeKind, "type", CppVariable, "name");

// Types for classes
alias CppClassName = Typedef!(string, string.init, "CppClassName");

///TODO should be Optional type, either it has a nesting or it is "global".
/// Don't check the length and use that as an insidential "no nesting".
alias CppClassNesting = Typedef!(string, string.init, "CppNesting");

alias CppClassVirtual = Typedef!(VirtualType, VirtualType.No, "CppClassVirtual");
alias CppClassInherit = Tuple!(CppClassName, "name", CppClassNesting,
    "nesting", CppAccess, "access");

// Types for methods
alias CppMethodName = Typedef!(string, string.init, "CppMethodName");
alias CppConstMethod = Typedef!(bool, bool.init, "CppConstMethod");
alias CppVirtualMethod = Typedef!(VirtualType, VirtualType.No, "CppVirtualMethod");
alias CppAccess = Typedef!(AccessType, AccessType.Private, "CppAccess");

// Types for free functions
alias CFunctionName = Typedef!(string, string.init, "CFunctionName");

// Shared types between C and Cpp
alias VariadicType = Flag!"isVariadic";
alias CxParam = Algebraic!(TypeKindVariable, TypeKind, VariadicType);
alias CxReturnType = Typedef!(TypeKind, TypeKind.init, "CxReturnType");

enum VirtualType {
    No,
    Yes,
    Pure
}

enum AccessType {
    Public,
    Protected,
    Private
}

/// Expects a toString function where it is mixed in.
/// base value for hash is 0 to force deterministic hashes. Use the pointer for
/// unique between objects.
private template mixinUniqueId() {
    private size_t id_;

    private size_t makeUniqueId() {
        import std.digest.crc;

        string str = this.toString();
        size_t value = 0;

        if (str is null)
            return value;
        ubyte[4] hash = crc32Of(str);
        return value ^ ((hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3]);
    }

    private void setUniqeId() {
        this.id_ = makeUniqueId();
    }

    size_t id() {
        return id_;
    }
}

/// User defined kind to differeniate structs of the same type.
private template mixinKind() {
    private int kind_;

    void setKind(int kind) {
        this.kind_ = kind;
    }

    @property const {
        auto kind() {
            return kind_;
        }
    }
}

/// Convert a namespace stack to a string separated by ::.
string toStringNs(CppNsStack ns) @safe {
    import std.algorithm : map;
    import std.array : join;

    return ns.map!(a => cast(string) a).join("::");
}

/// Convert a CxParam to a string.
string toInternal(CxParam p) @trusted {
    import std.variant : visit;

    // dfmt off
    return p.visit!(
        (TypeKindVariable tk) {return tk.type.toString ~ " " ~ tk.name.str;},
        (TypeKind t) { return t.toString; },
        (VariadicType a) { return "..."; }
        );
    // dfmt on
}

/// Join a range of CxParams to a string separated by ", ".
string joinParams(T)(T r) @safe if (isInputRange!T) {
    import std.algorithm : joiner, map;
    import std.conv : text;

    int uid;

    string getTypeName(T : const(Tx), Tx)(T p) @trusted {
        import std.variant : visit;

        // dfmt off
        return (cast(Tx) p).visit!(
            (TypeKindVariable tk) {return tk.type.toString ~ " " ~ tk.name.str;},
            (TypeKind t) { ++uid; return t.toString ~ " x" ~ text(uid); },
            (VariadicType a) { return "..."; }
            );
        // dfmt on
    }

    return r.map!(a => getTypeName(a)).joiner(", ").text();
}

/// Join a range of CxParams by extracting the parameter names.
string joinParamNames(T)(T r) @safe if (isInputRange!T) {
    import std.algorithm : joiner, map;
    import std.conv : text;

    int uid;

    string getName(T : const(Tx), Tx)(T p) @trusted {
        import std.variant : visit;

        // dfmt off
        return (cast(Tx) p).visit!(
            (TypeKindVariable tk) {return tk.name.str;},
            (TypeKind t) { ++uid; return "x" ~ text(uid); },
            (VariadicType a) { return ""; }
            );
        // dfmt on
    }

    return r.map!(a => getName(a)).joiner(", ").text();
}

/// Make a variadic parameter.
CxParam makeCxParam() @trusted {
    return CxParam(VariadicType.yes);
}

/// CParam created by analyzing a TypeKindVariable.
/// A empty variable name means it is of the algebraic type TypeKind.
CxParam makeCxParam(TypeKindVariable tk) @trusted {
    if (tk.name.length == 0)
        return CxParam(tk.type);
    return CxParam(tk);
}

private static void assertVisit(T : const(Tx), Tx)(ref T p) @trusted {
    import std.variant : visit;

    // dfmt off
    (cast(Tx) p).visit!(
        (TypeKindVariable tk) { assert(tk.name.length > 0);
                                assert(tk.type.name.length > 0);
                                assert(tk.type.toString.length > 0);},
        (TypeKind t) {  assert(t.name.length > 0);
                        assert(t.toString.length > 0); },
        (VariadicType a) {});
    // dfmt on
}

private void appInternal(CxParam p, ref Appender!string app) @trusted {
    import std.variant : visit;
    import std.format : formattedWrite;

    app.put(toInternal(p));
}

pure @safe nothrow struct CxGlobalVariable {
    mixin mixinUniqueId;

    @disable this();

    this(TypeKindVariable tk) {
        this.variable = tk;
    }

    this(TypeKind type, CppVariable name) {
        this(TypeKindVariable(type, name));
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.format : formattedWrite;
        import std.ascii : newline;

        auto app = appender!string();
        formattedWrite(app, "%s %s;%s", variable.type.toString, variable.name.str,
            newline);

        return app.data;
    }

    @property const {
        auto type() {
            return variable.type;
        }

        auto name() {
            return variable.name;
        }

        auto typeName() {
            return variable;
        }
    }

private:
    TypeKindVariable variable;
}

/// Information about free functions.
pure @safe nothrow struct CFunction {
    import std.typecons : TypedefType;

    mixin mixinUniqueId;

    @disable this();

    /// C function representation.
    this(const CFunctionName name, const CxParam[] params_,
        const CxReturnType return_type, const VariadicType is_variadic) {
        this.name_ = name;
        this.returnType_ = duplicate(cast(const TypedefType!CxReturnType) return_type);
        this.isVariadic_ = is_variadic;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }

        this.id_ = makeUniqueId();
    }

    /// Function with no parameters.
    this(const CFunctionName name, const CxReturnType return_type) {
        this(name, CxParam[].init, return_type, VariadicType.no);
    }

    /// Function with no parameters and returning void.
    this(const CFunctionName name) {
        CxReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CxParam[].init, void_, VariadicType.no);
    }

    /// A range over the parameters of the function.
    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    /// The return type of the function.
    auto returnType() const pure @safe @property {
        return returnType_;
    }

    /// Function name representation.
    auto name() @property const pure {
        return name_;
    }

    /// If the function is variadic, aka have a parameter with "...".
    bool isVariadic() {
        return VariadicType.yes == isVariadic_;
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;

        auto ps = appender!string();
        auto pr = paramRange();
        if (!pr.empty) {
            appInternal(pr.front, ps);
            pr.popFront;
            pr.each!((a) { ps.put(", "); appInternal(a, ps); });
        }

        auto rval = appender!string();
        formattedWrite(rval, "%s %s(%s);%s", returnType.toString, name.str, ps.data,
            newline);

        return rval.data;
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.name.length > 0);
        assert(returnType_.toString.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    CFunctionName name_;

    CxParam[] params;
    CxReturnType returnType_;
    VariadicType isVariadic_;
}

pure @safe nothrow struct CppCtor {
    import std.typecons : TypedefType;

    mixin mixinUniqueId;

    @disable this();

    this(const CppMethodName name, const CxParam[] params_, const CppAccess access) {
        this.name_ = name;
        this.accessType_ = access;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }

        this.id_ = makeUniqueId();
    }

    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    string toString() const @safe {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;

        auto ps = appender!string();
        auto pr = paramRange();
        if (!pr.empty) {
            appInternal(pr.front, ps);
            pr.popFront;
            pr.each!((a) { ps.put(", "); appInternal(a, ps); });
        }

        auto rval = appender!string();
        formattedWrite(rval, "%s(%s)", name_.str, ps.data);

        return rval.data;
    }

    @property const {
        auto accessType() {
            return accessType_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        assert(name_.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    CppAccess accessType_;

    CppMethodName name_;
    CxParam[] params;
}

pure @safe nothrow struct CppDtor {
    import std.typecons : TypedefType;

    mixin mixinUniqueId;

    @disable this();

    this(const CppMethodName name, const CppAccess access, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.accessType_ = access;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;

        this.id_ = makeUniqueId();
    }

    string toString() const @safe {
        import std.array : appender;

        auto rval = appender!string();
        switch (isVirtual) {
        case VirtualType.Yes:
        case VirtualType.Pure:
            rval.put("virtual ");
            break;
        default:
        }
        rval.put(name_.str);
        rval.put("()");

        return rval.data;
    }

    @property const {
        bool isVirtual() {
            return isVirtual_ != VirtualType.No;
        }

        auto virtualType() {
            return isVirtual_;
        }

        auto accessType() {
            return accessType_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        assert(name_.length > 0);
        assert(isVirtual_ != VirtualType.Pure);
    }

private:
    VirtualType isVirtual_;
    CppAccess accessType_;

    CppMethodName name_;
}

pure @safe nothrow struct CppMethod {
    import std.typecons : TypedefType;

    mixin mixinUniqueId;

    @disable this();

    this(const CppMethodName name, const CxParam[] params_,
        const CxReturnType return_type, const CppAccess access,
        const CppConstMethod const_, const CppVirtualMethod virtual) {
        this.name_ = name;
        this.returnType_ = duplicate(cast(const TypedefType!CxReturnType) return_type);
        this.accessType_ = access;
        this.isConst_ = cast(TypedefType!CppConstMethod) const_;
        this.isVirtual_ = cast(TypedefType!CppVirtualMethod) virtual;

        //TODO how do you replace this with a range?
        foreach (p; params_) {
            this.params ~= p;
        }

        this.id_ = makeUniqueId();
    }

    /// Function with no parameters.
    this(const CppMethodName name, const CxReturnType return_type,
        const CppAccess access, const CppConstMethod const_, const CppVirtualMethod virtual) {
        this(name, CxParam[].init, return_type, access, const_, virtual);
    }

    /// Function with no parameters and returning void.
    this(const CppMethodName name, const CppAccess access,
        const CppConstMethod const_ = false, const CppVirtualMethod virtual = VirtualType.No) {
        CxReturnType void_ = makeTypeKind("void", "void", false, false, false);
        this(name, CxParam[].init, void_, access, const_, virtual);
    }

    void put(const CxParam p) {
        params ~= p;
    }

    auto paramRange() const @nogc @safe pure nothrow {
        return arrayRange(params);
    }

    string toString() const @safe {
        import std.array : appender;
        import std.algorithm : each;
        import std.format : formattedWrite;

        auto ps = appender!string();
        auto pr = paramRange();
        if (!pr.empty) {
            appInternal(pr.front, ps);
            pr.popFront;
            pr.each!((a) { ps.put(", "); appInternal(a, ps); });
        }

        auto rval = appender!string();
        switch (virtualType()) {
        case VirtualType.Yes:
        case VirtualType.Pure:
            rval.put("virtual ");
            break;
        default:
        }
        formattedWrite(rval, "%s %s(%s)", returnType_.toString, name_.str, ps.data);

        if (isConst) {
            rval.put(" const");
        }
        switch (virtualType()) {
        case VirtualType.Pure:
            rval.put(" = 0");
            break;
        default:
        }

        return rval.data;
    }

    @property const {
        auto isConst() {
            return isConst_;
        }

        bool isVirtual() {
            return isVirtual_ != VirtualType.No;
        }

        auto virtualType() {
            return isVirtual_;
        }

        auto accessType() {
            return accessType_;
        }

        auto returnType() {
            return returnType_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        assert(name_.length > 0);
        assert(returnType_.name.length > 0);
        assert(returnType_.toString.length > 0);

        foreach (p; params) {
            assertVisit(p);
        }
    }

private:
    bool isConst_;
    VirtualType isVirtual_;
    CppAccess accessType_;

    CppMethodName name_;
    CxParam[] params;
    CxReturnType returnType_;
}

pure @safe nothrow struct CppClass {
    import std.variant : Algebraic, visit;
    import std.typecons : TypedefType;

    alias CppFunc = Algebraic!(CppMethod, CppCtor, CppDtor);

    mixin mixinUniqueId;
    mixin mixinKind;

    @disable this();

    this(const CppClassName name, const CppClassInherit[] inherits) {
        this.name_ = name;
        this.inherits_ = inherits.dup;

        this.id_ = makeUniqueId();
    }

    this(const CppClassName name) {
        this(name, CppClassInherit[].init);
    }

    void put(T)(T func) @trusted if (is(T == CppMethod) || is(T == CppCtor) || is(T == CppDtor)) {
        final switch (cast(TypedefType!CppAccess) func.accessType) {
        case AccessType.Public:
            methods_pub ~= CppFunc(func);
            break;
        case AccessType.Protected:
            methods_prot ~= CppFunc(func);
            break;
        case AccessType.Private:
            methods_priv ~= CppFunc(func);
            break;
        }

        isVirtual_ = analyzeVirtuality(this);
    }

    void put(T)(T class_, AccessType accessType) @trusted if (is(T == CppClass)) {
        final switch (accessType) {
        case AccessType.Public:
            classes_pub ~= class_;
            break;
        case AccessType.Protected:
            classes_prot ~= class_;
            break;
        case AccessType.Private:
            classes_priv ~= class_;
            break;
        }
    }

    /// Add a comment string to the class.
    void put(string comment) {
        cmnt ~= comment;
    }

    auto inheritRange() const @nogc @safe pure nothrow {
        return arrayRange(inherits_);
    }

    auto methodRange() @nogc @safe pure nothrow {
        import std.range : chain;

        return chain(methods_pub, methods_prot, methods_priv);
    }

    auto methodPublicRange() @nogc @safe pure nothrow {
        return arrayRange(methods_pub);
    }

    auto methodProtectedRange() @nogc @safe pure nothrow {
        return arrayRange(methods_prot);
    }

    auto methodPrivateRange() @nogc @safe pure nothrow {
        return arrayRange(methods_priv);
    }

    auto classRange() @nogc @safe pure nothrow {
        import std.range : chain;

        return chain(classes_pub, classes_prot, classes_priv);
    }

    auto classPublicRange() @nogc @safe pure nothrow {
        return arrayRange(classes_pub);
    }

    auto classProtectedRange() @nogc @safe pure nothrow {
        return arrayRange(classes_prot);
    }

    auto classPrivateRange() @nogc @safe pure nothrow {
        return arrayRange(classes_priv);
    }

    auto commentRange() const @nogc @safe pure nothrow {
        return arrayRange(cmnt);
    }

    ///TODO make the function const.
    string toString() const @safe {
        import std.array : Appender, appender;
        import std.conv : to;
        import std.algorithm : each;
        import std.ascii : newline;
        import std.format : formattedWrite;

        static void updateVirt(T : const(Tx), Tx)(ref T th) @trusted {
            if (StateType.Dirty == th.st) {
                (cast(Tx) th).isVirtual_ = analyzeVirtuality(cast(Tx) th);
                (cast(Tx) th).st = StateType.Clean;
            }
        }

        updateVirt(this);

        static string funcToString(CppFunc func) @trusted {
            //dfmt off
            return func.visit!((CppMethod a) => a.toString,
                               (CppCtor a) => a.toString,
                               (CppDtor a) => a.toString);
            //dfmt on
        }

        static void appPubRange(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            if (th.methods_pub.length > 0 || th.classes_pub.length > 0) {
                formattedWrite(app, "public:%s", newline);
                (cast(Tx) th).methodPublicRange.each!(a => formattedWrite(app,
                    "  %s;%s", funcToString(a), newline));
                (cast(Tx) th).classPublicRange.each!(a => app.put(a.toString()));
            }
        }

        static void appProtRange(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            if (th.methods_prot.length > 0 || th.classes_prot.length > 0) {
                formattedWrite(app, "protected:%s", newline);
                (cast(Tx) th).methodProtectedRange.each!(a => formattedWrite(app,
                    "  %s;%s", funcToString(a), newline));
                (cast(Tx) th).classProtectedRange.each!(a => app.put(a.toString()));
            }
        }

        static void appPrivRange(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            if (th.methods_priv.length > 0 || th.classes_priv.length > 0) {
                formattedWrite(app, "private:%s", newline);
                (cast(Tx) th).methodPrivateRange.each!(a => formattedWrite(app,
                    "  %s;%s", funcToString(a), newline));
                (cast(Tx) th).classPrivateRange.each!(a => app.put(a.toString()));
            }
        }

        static string inheritRangeToString(T)(T range) @trusted {
            import std.range : enumerate;
            import std.string : toLower;

            auto app = appender!string();
            // dfmt off
            range.enumerate(0)
                .each!(a => formattedWrite(app, "%s%s %s%s",
                       a.index == 0 ? " : " : ", ",
                       to!string(cast (TypedefType!(typeof(a.value.access))) a.value.access).toLower,
                       a.value.nesting.str,
                       a.value.name.str));
            // dfmt on

            return app.data;
        }

        auto app = appender!string();

        commentRange().each!(a => formattedWrite(app, "// %s%s", a, newline));

        formattedWrite(app, "class %s%s { // isVirtual %s%s", name_.str,
            inheritRangeToString(inheritRange()), to!string(virtualType()), newline);
        appPubRange(this, app);
        appProtRange(this, app);
        appPrivRange(this, app);
        formattedWrite(app, "}; //Class:%s%s", name_.str, newline);

        return app.data;
    }

    invariant() {
        assert(name_.length > 0);
        foreach (i; inherits_) {
            assert(i.name.length > 0);
        }
    }

    @property const {
        bool isVirtual() {
            return isVirtual_ != VirtualType.No;
        }

        auto virtualType() {
            return isVirtual_;
        }

        auto name() {
            return name_;
        }

        auto inherits() {
            return inherits_;
        }
    }

private:
    // Dirty if the virtuality has to be recalculated.
    enum StateType {
        Dirty,
        Clean
    }

    StateType st;

    CppClassName name_;
    CppClassInherit[] inherits_;

    VirtualType isVirtual_;

    CppFunc[] methods_pub;
    CppFunc[] methods_prot;
    CppFunc[] methods_priv;

    CppClass[] classes_pub;
    CppClass[] classes_prot;
    CppClass[] classes_priv;

    string[] cmnt;
}

// Clang have no function that says if a class is virtual/pure virtual.
// So have to post process.
private VirtualType analyzeVirtuality(CppClass th) @safe {
    static auto getVirt(CppClass.CppFunc func) @trusted {
        import std.variant : visit;

        //dfmt off
        return func.visit!((CppMethod a) => a.virtualType(),
                           (CppCtor a) => VirtualType.Pure,
                           (CppDtor a) {return a.isVirtual() ? VirtualType.Pure : VirtualType.No;});
        //dfmt on
    }

    auto mr = th.methodRange();
    auto v = VirtualType.No;
    if (!mr.empty) {
        v = getVirt(mr.front);
        mr.popFront();
    }
    foreach (m; mr) {
        const auto mVirt = getVirt(m);

        final switch (th.isVirtual_) {
        case VirtualType.Pure:
            v = mVirt;
            break;
        case VirtualType.Yes:
            if (mVirt != VirtualType.Pure) {
                v = mVirt;
            }
            break;
        case VirtualType.No:
            break;
        }
    }

    return v;
}

pure @safe nothrow struct CppNamespace {
    @disable this();

    mixin mixinUniqueId;
    mixin mixinKind;

    static auto makeAnonymous() {
        return CppNamespace(CppNsStack.init);
    }

    /// A namespace without any nesting.
    static auto make(CppNs name) {
        return CppNamespace([name]);
    }

    this(const CppNsStack stack) {
        if (stack.length > 0) {
            this.name_ = stack[$ - 1];
        }
        this.isAnonymous_ = stack.length == 0;
        this.stack = stack.dup;

        this.id_ = makeUniqueId();
    }

    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    void put(CppNamespace ns) {
        namespaces ~= ns;
    }

    void put(CxGlobalVariable g) {
        globals ~= g;
    }

    /** Traverse stack from top to bottom.
     * The implementation of the stack is such that new elements are appended
     * to the end. Therefor the range normal direction is from the end of the
     * array to the beginning.
     */
    auto nsNestingRange() @nogc @safe pure nothrow {
        import std.range : retro;

        return arrayRange(stack).retro;
    }

    auto classRange() @nogc @safe pure nothrow {
        return arrayRange(classes);
    }

    auto funcRange() @nogc @safe pure nothrow {
        return arrayRange(funcs);
    }

    auto namespaceRange() @nogc @safe pure nothrow {
        return arrayRange(namespaces);
    }

    auto globalRange() @nogc @safe pure nothrow {
        return arrayRange(globals);
    }

    string toString() const @safe {
        import std.array : Appender, appender;
        import std.algorithm : each;
        import std.format : formattedWrite;
        import std.range : retro;
        import std.ascii : newline;

        static void appRanges(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            (cast(Tx) th).globalRange.each!(a => app.put(a.toString()));
            (cast(Tx) th).funcRange.each!(a => app.put(a.toString));
            (cast(Tx) th).classRange.each!(a => app.put(a.toString));
            (cast(Tx) th).namespaceRange.each!(a => app.put(a.toString));
        }

        static void nsToStrings(T : const(Tx), Tx)(ref T th, out string ns_name, out string ns_concat) @trusted {
            auto ns_app = appender!string();
            ns_name = "";
            ns_concat = "";

            auto ns_r = (cast(Tx) th).nsNestingRange().retro;
            if (!ns_r.empty) {
                ns_name = ns_r.back.str;
                ns_app.put(ns_r.front.str);
                ns_r.popFront;
                ns_r.each!(a => formattedWrite(ns_app, "::%s", a.str));
                ns_concat = ns_app.data;
            }
        }

        string ns_name;
        string ns_concat;
        nsToStrings(this, ns_name, ns_concat);

        auto app = appender!string();
        formattedWrite(app, "namespace %s { //%s%s", ns_name, ns_concat, newline);
        appRanges(this, app);
        formattedWrite(app, "} //NS:%s%s", ns_name, newline);

        return app.data;
    }

    @property const {
        auto isAnonymous() {
            return isAnonymous_;
        }

        auto name() {
            return name_;
        }
    }

    invariant() {
        foreach (s; stack) {
            assert(s.length > 0);
        }
    }

private:
    bool isAnonymous_;
    CppNs name_;

    CppNsStack stack;
    CppClass[] classes;
    CFunction[] funcs;
    CppNamespace[] namespaces;
    CxGlobalVariable[] globals;
}

pure @safe nothrow struct CppRoot {
    void put(CFunction f) {
        funcs ~= f;
    }

    void put(CppClass s) {
        classes ~= s;
    }

    void put(CppNamespace ns) {
        this.ns ~= ns;
    }

    void put(CxGlobalVariable g) {
        globals ~= g;
    }

    string toString() const @safe {
        import std.array : Appender, appender;

        static void appRanges(T : const(Tx), Tx)(ref T th, ref Appender!string app) @trusted {
            import std.algorithm : each;
            import std.ascii : newline;
            import std.format : formattedWrite;

            if (th.globals.length > 0) {
                (cast(Tx) th).globalRange.each!(a => app.put(a.toString()));
                app.put(newline);
            }

            if (th.funcs.length > 0) {
                (cast(Tx) th).funcRange.each!(a => app.put(a.toString));
                app.put(newline);
            }

            if (th.classes.length > 0) {
                (cast(Tx) th).classRange.each!(a => app.put(a.toString));
                app.put(newline);
            }

            (cast(Tx) th).namespaceRange.each!(a => app.put(a.toString));
        }

        auto app = appender!string();
        appRanges(this, app);

        return app.data;
    }

    auto namespaceRange() @nogc @safe pure nothrow {
        return arrayRange(ns);
    }

    auto classRange() @nogc @safe pure nothrow {
        return arrayRange(classes);
    }

    auto funcRange() @nogc @safe pure nothrow {
        return arrayRange(funcs);
    }

    auto globalRange() @nogc @safe pure nothrow {
        return arrayRange(globals);
    }

private:
    CppNamespace[] ns;
    CppClass[] classes;
    CFunction[] funcs;
    CxGlobalVariable[] globals;
}

/// Find where in the structure a class with the uniqe id reside.
@safe CppNsStack whereIsClass(CppRoot root, const size_t id) {
    CppNsStack ns;

    foreach (c; root.classRange()) {
        if (c.id() == id) {
            return ns;
        }
    }

    return ns;
}

@name("Test of c-function")
unittest {
    { // simple version, no return or parameters.
        auto f = CFunction(CFunctionName("nothing"));
        shouldEqual(f.returnType.name, "void");
        shouldEqual(f.toString, "void nothing();\n");
    }

    { // a return type.
        auto rtk = makeTypeKind("int", "int", false, false, false);
        auto f = CFunction(CFunctionName("nothing"), CxReturnType(rtk));
        shouldEqual(f.toString, "int nothing();\n");
    }

    { // return type and parameters.
        auto p0 = makeCxParam(TypeKindVariable(makeTypeKind("int", "int",
            false, false, false), CppVariable("x")));
        auto p1 = makeCxParam(TypeKindVariable(makeTypeKind("char", "char",
            false, false, false), CppVariable("y")));
        auto rtk = makeTypeKind("int", "int", false, false, false);
        auto f = CFunction(CFunctionName("nothing"), [p0, p1], CxReturnType(rtk), VariadicType.no);
        shouldEqual(f.toString, "int nothing(int x, char y);\n");
    }
}

@name("Test of creating simples CppMethod")
unittest {
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    shouldEqual(m.isConst, false);
    shouldEqual(m.isVirtual, VirtualType.No);
    shouldEqual(m.name, "voider");
    shouldEqual(m.params.length, 0);
    shouldEqual(m.returnType.name, "void");
    shouldEqual(m.accessType, AccessType.Public);
}

@name("Test creating a CppMethod with multiple parameters")
unittest {
    auto tk = makeTypeKind("char", "char*", false, false, true);
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto m = CppMethod(CppMethodName("none"), [p, p], CxReturnType(tk),
        CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(VirtualType.Yes));

    shouldEqual(m.toString, "virtual char* none(char* x, char* x) const");
}

@name("Test of creating a class")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    shouldEqual(c.methods_pub.length, 1);
    shouldEqualPretty(c.toString,
        "class Foo { // isVirtual No\npublic:\n  void voider();\n}; //Class:Foo\n");
}

@name("Create an anonymous namespace struct")
unittest {
    auto n = CppNamespace(CppNsStack.init);
    shouldEqual(n.name.length, 0);
    shouldEqual(n.isAnonymous, true);
}

@name("Create a namespace struct two deep")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    shouldEqual(n.name, "bar");
    shouldEqual(n.isAnonymous, false);
}

@name("Test of iterating over parameters in a class")
unittest {
    import std.array : appender;

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);

    auto app = appender!string();
    foreach (d; c.methodRange) {
        app.put(d.toString());
    }

    shouldEqual(app.data, "void voider()");
}

@name("Test of toString for a free function")
unittest {
    auto ptk = makeTypeKind("char", "char*", false, false, true);
    auto rtk = makeTypeKind("int", "int", false, false, false);
    auto f = CFunction(CFunctionName("nothing"),
        [makeCxParam(TypeKindVariable(ptk, CppVariable("x"))),
        makeCxParam(TypeKindVariable(ptk, CppVariable("y")))], CxReturnType(rtk), VariadicType.no);

    shouldEqualPretty(f.toString, "int nothing(char* x, char* y);\n");
}

@name("Test of Ctor's")
unittest {
    auto tk = makeTypeKind("char", "char*", false, false, true);
    auto p = CxParam(TypeKindVariable(tk, CppVariable("x")));

    auto ctor = CppCtor(CppMethodName("ctor"), [p, p], CppAccess(AccessType.Public));

    shouldEqual(ctor.toString, "ctor(char* x, char* x)");
}

@name("Test of Dtor's")
unittest {
    auto dtor = CppDtor(CppMethodName("~dtor"), CppAccess(AccessType.Public),
        CppVirtualMethod(VirtualType.Yes));

    shouldEqual(dtor.toString, "virtual ~dtor()");
}

@name("Test of toString for CppClass")
unittest {
    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public)));

    {
        auto m = CppCtor(CppMethodName("Foo"), CxParam[].init, CppAccess(AccessType.Public));
        c.put(m);
    }

    {
        auto tk = makeTypeKind("int", "int", false, false, false);
        auto m = CppMethod(CppMethodName("fun"), CxReturnType(tk),
            CppAccess(AccessType.Protected), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("gun"),
            CxReturnType(makeTypeKind("char", "char*", false, false, true)),
            CppAccess(AccessType.Private), CppConstMethod(false),
            CppVirtualMethod(VirtualType.No));
        m.put(CxParam(TypeKindVariable(makeTypeKind("int", "int", false, false,
            false), CppVariable("x"))));
        m.put(CxParam(TypeKindVariable(makeTypeKind("int", "int", false, false,
            false), CppVariable("y"))));
        c.put(m);
    }

    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeTypeKind("int", "int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(true), CppVirtualMethod(VirtualType.No));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // isVirtual No
public:
  void voider();
  Foo();
  int wun() const;
protected:
  virtual int fun() = 0;
private:
  char* gun(int x, int y);
}; //Class:Foo
");
}

@name("should contain the inherited classes")
unittest {
    CppClassInherit[] inherit;
    inherit ~= CppClassInherit(CppClassName("pub"), CppClassNesting(""),
        CppAccess(AccessType.Public));
    inherit ~= CppClassInherit(CppClassName("prot"), CppClassNesting(""),
        CppAccess(AccessType.Protected));
    inherit ~= CppClassInherit(CppClassName("priv"), CppClassNesting(""),
        CppAccess(AccessType.Private));

    auto c = CppClass(CppClassName("Foo"), inherit);

    shouldEqualPretty(c.toString,
        "class Foo : public pub, protected prot, private priv { // isVirtual No
}; //Class:Foo
");
}

@name("should contain nested classes")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    c.put(CppClass(CppClassName("Pub")), AccessType.Public);
    c.put(CppClass(CppClassName("Prot")), AccessType.Protected);
    c.put(CppClass(CppClassName("Priv")), AccessType.Private);

    shouldEqualPretty(c.toString, "class Foo { // isVirtual No
public:
class Pub { // isVirtual No
}; //Class:Pub
protected:
class Prot { // isVirtual No
}; //Class:Prot
private:
class Priv { // isVirtual No
}; //Class:Priv
}; //Class:Foo
");
}

@name("should be a virtual class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppDtor(CppMethodName("~Foo"), CppAccess(AccessType.Public),
            CppVirtualMethod(VirtualType.Yes));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeTypeKind("int", "int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Yes));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Yes
public:
  virtual ~Foo();
  virtual int wun();
}; //Class:Foo
");
}

@name("should be a pure virtual class")
unittest {
    auto c = CppClass(CppClassName("Foo"));

    {
        auto m = CppDtor(CppMethodName("~Foo"), CppAccess(AccessType.Public),
            CppVirtualMethod(VirtualType.Yes));
        c.put(m);
    }
    {
        auto m = CppMethod(CppMethodName("wun"),
            CxReturnType(makeTypeKind("int", "int", false, false, true)),
            CppAccess(AccessType.Public), CppConstMethod(false),
            CppVirtualMethod(VirtualType.Pure));
        c.put(m);
    }

    shouldEqualPretty(c.toString, "class Foo { // isVirtual Pure
public:
  virtual ~Foo();
  virtual int wun() = 0;
}; //Class:Foo
");
}

@name("Test of toString for CppNamespace")
unittest {
    auto ns = CppNamespace.make(CppNs("simple"));

    auto c = CppClass(CppClassName("Foo"));
    c.put(CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public)));
    ns.put(c);

    shouldEqualPretty(ns.toString, "namespace simple { //simple
class Foo { // isVirtual No
public:
  void voider();
}; //Class:Foo
} //NS:simple
");
}

@name("Should show nesting of namespaces as valid C++ code")
unittest {
    auto stack = [CppNs("foo"), CppNs("bar")];
    auto n = CppNamespace(stack);
    shouldEqualPretty(n.toString, "namespace bar { //foo::bar
} //NS:bar
");
}

@name("Test of toString for CppRoot")
unittest {
    CppRoot root;

    { // free function
        auto f = CFunction(CFunctionName("nothing"));
        root.put(f);
    }

    auto c = CppClass(CppClassName("Foo"));
    auto m = CppMethod(CppMethodName("voider"), CppAccess(AccessType.Public));
    c.put(m);
    root.put(c);

    root.put(CppNamespace.make(CppNs("simple")));

    shouldEqualPretty(root.toString, "void nothing();

class Foo { // isVirtual No
public:
  void voider();
}; //Class:Foo

namespace simple { //simple
} //NS:simple
");
}

@name("CppNamespace.toString should return nested namespace")
unittest {
    auto stack = [CppNs("Depth1"), CppNs("Depth2"), CppNs("Depth3")];
    auto depth1 = CppNamespace(stack[0 .. 1]);
    auto depth2 = CppNamespace(stack[0 .. 2]);
    auto depth3 = CppNamespace(stack[0 .. $]);

    depth2.put(depth3);
    depth1.put(depth2);

    shouldEqualPretty(depth1.toString, "namespace Depth1 { //Depth1
namespace Depth2 { //Depth1::Depth2
namespace Depth3 { //Depth1::Depth2::Depth3
} //NS:Depth3
} //NS:Depth2
} //NS:Depth1
");
}

@name("Create anonymous namespace")
unittest {
    auto n = CppNamespace.makeAnonymous();

    shouldEqualPretty(n.toString, "namespace  { //
} //NS:
");
}

@name("Add a C-func to a namespace")
unittest {
    auto n = CppNamespace.makeAnonymous();
    auto f = CFunction(CFunctionName("nothing"));
    n.put(f);

    shouldEqualPretty(n.toString, "namespace  { //
void nothing();
} //NS:
");
}

@name("should be a hash value based on string representation")
unittest {
    struct A {
        mixin mixinUniqueId;
        this(bool fun) {
            setUniqeId();
        }

        auto toString() {
            return "foo";
        }
    }

    auto a = A(true);
    auto b = A(true);

    shouldBeGreaterThan(a.makeUniqueId(), 0);
    shouldBeGreaterThan(a.id(), 0);
    shouldEqual(a.id(), b.id());
}

@name("should be a global definition")
unittest {
    auto v0 = CxGlobalVariable(TypeKindVariable(makeTypeKind("int", "int",
        false, false, false), CppVariable("x")));
    auto v1 = CxGlobalVariable(makeTypeKind("int", "int", false, false, false), CppVariable("y"));

    shouldEqualPretty(v0.toString, "int x;\n");
    shouldEqualPretty(v1.toString, "int y;\n");
}

@name("globals in root")
unittest {
    auto v = CxGlobalVariable(TypeKindVariable(makeTypeKind("int", "int",
        false, false, false), CppVariable("x")));
    auto n = CppNamespace.makeAnonymous();
    auto r = CppRoot();
    n.put(v);
    r.put(v);
    r.put(n);

    shouldEqualPretty(r.toString, "int x;

namespace  { //
int x;
} //NS:
");
}