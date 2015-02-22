class Simple2 {
public:
    Simple2();
    ~Simple2();

    void func1() { int foo = 1; foo++; }
    int func2();

private:
    int x;
};

int Simple2::func2() {
    int y = 3;
    return y;
}
