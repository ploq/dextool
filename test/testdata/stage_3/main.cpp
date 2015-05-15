/** @file main.cpp
 * @brief Functional test of stubs.
 * @author Joakim Brännström (joakim.brannstrom@gmx.com)
 * @date 2015
 * @copyright GNU Licence
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include "stub_ifs1.hpp"
#include <iostream>
#include <assert.h>

#define start_test() do{std::cout << " # " <<  __func__ << "\t\t" << __FILE__ << ":" << __LINE__ << std::endl;}while(0)
#define msg(x) do{std::cout << __FILE__ << ":" << __LINE__ << " " << x << std::endl;}while(0)

void test_stack_instance() {
    start_test();
    StubIfs1 stub;
}

void test_heap_instance() {
    start_test();
    Ifs1* obj = new StubIfs1;
    delete obj;
}

// --- White box testing of init functions ---
void test_init_counters() {
    start_test();
    StubIfs1 stub;

    stub.StubGet().run().call_counter = 42;
    StubInternalIfs1::StubInit(&stub.StubGet().run());
    assert(stub.StubGet().run().call_counter == 0);
}

void test_init_static() {
    start_test();
    StubIfs1 stub;

    stub.StubGet().ifs2_func1_int_char().stub_return = 42;
    StubInternalIfs1::StubInit(&stub.StubGet().ifs2_func1_int_char());
    assert(stub.StubGet().ifs2_func1_int_char().stub_return == 0);
}

void test_init_callback() {
    start_test();
    StubIfs1 stub;

    stub.StubGet().run().callback = reinterpret_cast<StubCallbackIfs1::Irun*>(42);
    StubInternalIfs1::StubInit(&stub.StubGet().run());
    assert(stub.StubGet().run().callback == 0);
}
// --- End testing of init functions ---

void test_call_counter() {
    start_test();
    StubIfs1 stub;
    Ifs1* obj = &stub;

    msg("Counter is initialized to zero");
    assert(stub.StubGet().run().call_counter == 0);
    assert(stub.StubGet().ifs2_func1_int_char().call_counter == 0);

    msg("Calling func with no params via the interface ptr");
    obj->run();
    assert(stub.StubGet().run().call_counter > 0);

    msg("Calling func with parameters via the interface ptr");
    obj->ifs2_func1(42, 'x');
    assert(stub.StubGet().ifs2_func1_int_char().call_counter > 0);
}

void test_static_return() {
    start_test();
    StubIfs1 stub;
    Ifs1* obj = &stub;

    stub.StubGet().ifs2_func1_int_char().stub_return = 42;
    assert(obj->ifs2_func1(42, 'x') == 42);
}

void test_static_param_stored() {
    start_test();
    StubIfs1 stub;
    Ifs1* obj = &stub;

    obj->ifs2_func1(42, 'x');
    assert(stub.StubGet().ifs2_func1_int_char().param_x0 == 42);
    assert(stub.StubGet().ifs2_func1_int_char().param_x1 == 'x');
}

class TestCallback : public StubCallbackIfs1::Irun,
    public StubCallbackIfs1::Iifs2_func1_int_char,
    public StubCallbackIfs1::Iget_ifc3 {
public:
    TestCallback() : called(false), x0(0), x1(0) {}
    ~TestCallback() {}

    void run() {
        called = true;
    }
    bool called;

    int ifs2_func1_int_char(int v, char c) {
        x0 = v;
        x1 = c;
        return 42;
    }
    int x0;
    char x1;

    Ifs3& get_ifc3() {
        return ifs3_inst;
    }
    StubIfs3 ifs3_inst;
};

void test_callback_simple() {
    start_test();
    TestCallback cb;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    // Configure stub with callback
    stub.StubGet().run().callback = &cb;
    assert(cb.called == false);

    msg("Expecting a callback and thus changing callback objects variable called to true");
    obj->run();
    assert(cb.called == true);

    msg("Expect call counter to increment even though a callback was used");
    assert(stub.StubGet().run().call_counter > 0);
}

void test_callback_params() {
    start_test();
    TestCallback cb;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    // Configure stub with callback
    stub.StubGet().ifs2_func1_int_char().callback = &cb;

    msg("Callback func with params");
    assert(obj->ifs2_func1(8, 'a') == 42);
    assert(cb.x0 == 8);
    assert(cb.x1 == 'a');

    msg("Expect call counter to increment even though a callback was used");
    assert(stub.StubGet().ifs2_func1_int_char().call_counter > 0);
}

void test_callback_return_obj() {
    start_test();
    TestCallback cb;
    StubIfs1 stub;
    Ifs1* obj = &stub;

    // Configure stub with callback
    stub.StubGet().get_ifc3().callback = &cb;

    msg("Callback returning obj via ref");
    Ifs3& i3 = obj->get_ifc3();
    i3.dostuff();

    msg("Expect call counter to increment even though a callback was used");
    assert(stub.StubGet().get_ifc3().call_counter > 0);

    msg("Expect call counter in returned objects to increment");
    assert(cb.ifs3_inst.StubGet().dostuff().call_counter > 0);
}

int main(int argc, char** argv) {
    std::cout << "functional testing of stub of Ifs1" << std::endl;

    test_stack_instance();
    test_heap_instance();
    test_init_counters();
    test_init_static();
    test_init_callback();
    test_call_counter();
    test_static_return();
    test_static_param_stored();
    test_callback_simple();
    test_callback_params();
    test_callback_return_obj();

    return 0;
}
