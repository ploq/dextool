// The C AST is different from the C++
// Should detect func as a function and not simple.
// Move this to cstub/stage_1

typedef void* void_ptr;
typedef void_ptr(typedef_func)();

extern typedef_func func;
