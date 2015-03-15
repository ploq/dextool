typedef char* some_pointer;

class Simple {
public:
    Simple();
    Simple(char foo);
    ~Simple();

    void func1();
    int func2();
    char* func6(some_pointer w);
    float func7(int& y, char* yy);
    const double func3(int x, const int xx);
    const void* const func4(MadeUp z, const MadeUp zz, const MadeUp& zzz, const MadeUp** const zzzz);

private:
    int x;
};
