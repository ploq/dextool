#ifndef FUNCTIONS_BODY_CALL_HPP
#define FUNCTIONS_BODY_CALL_HPP

typedef int MyInt;

void empty() {
}

int arg0(MyInt) {
    return 1;
}

MyInt arg1(int) {
    return MyInt(2);
}

void single_call() {
    empty();
}

void if_() {
    if (arg0(3) > 10) {
        empty();
    } else {
        empty();
    }
}

void for_() {
    for (int for_x = arg0(2); for_x < 10; ++for_x) {
        empty();
    }
}

void nested() {
    arg0(arg1(3));
}

#endif // FUNCTIONS_BODY_CALL_HPP
