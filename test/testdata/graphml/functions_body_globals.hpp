#ifndef FUNCTIONS_BODY_GLOBALS_HPP
#define FUNCTIONS_BODY_GLOBALS_HPP

int global;

void read_access() {
    int x = global;
}

void assign_access() {
    global = 2;
}

#endif // FUNCTIONS_BODY_GLOBALS_HPP
