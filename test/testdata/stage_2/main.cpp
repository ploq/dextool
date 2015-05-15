#include "stub_ifs1.hpp"
#include <iostream>

int main(int argc, char** argv) {
    std::cout << "it works" << std::endl;

    StubIfs1 stub;
    stub.run();
    stub.get_ifc2();
    stub.get_ifc3();
    stub.ifs2_func1(42, 'x');

    stub.StubGet().ifs2_func1_int_char();
    stub.StubGet().run();
    stub.StubGet().get_ifc2();
    stub.StubGet().get_ifc3();
    stub.StubGet().StubDtor();

    return 0;
}
