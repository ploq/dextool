// Contains a C++ interface. Pure virtual.
// Expecting an implementation.

class Simple {
public:
    Simple();
    ~Simple();

    virtual void func1() = 0;
    void operator=(const Simple& other) = 0;

private:
    virtual char* func3() = 0;
};
