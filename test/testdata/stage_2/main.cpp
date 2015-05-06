#include "stub_ifs1.hpp"
#include <iostream>

int main(int argc, char** argv) {
    std::cout << "it works" << std::endl;

    StubIfs1 stub;
    stub.run();
    stub.get_ifc2();
    stub.get_ifc3();
    stub.ifs2_func1(42, 'x');

    stub.StubGetCallback();
    stub.StubGetCounter();
    stub.StubGetStatic();

    return 0;
}
