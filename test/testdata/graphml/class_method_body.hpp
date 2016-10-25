#ifndef CLASS_METHOD_BODY_HPP
#define CLASS_METHOD_BODY_HPP

void ctor();
void copy_ctor();
void dtor();
void method();

class InlineMethods {
public:
    InlineMethods() {
        ctor();
    }
    InlineMethods(const InlineMethods&) {
        copy_ctor();
    }
    ~InlineMethods() {
        dtor();
    }

    void func() {
        method();
    }
};

class Methods {
public:
    Methods();
    Methods(const Methods&);
    ~Methods();

    void func();
};

Methods::Methods() {
    ctor();
}
Methods::Methods(const Methods&) {
    copy_ctor();
}
Methods::~Methods() {
    dtor();
}
void Methods::func() {
    method();
}

class Dummy {
public:
    void fun() {}
};

class CallOtherClass {
public:
    void func() {
        a.fun();
    }

    Dummy a;
};

#endif // CLASS_METHOD_BODY_HPP
