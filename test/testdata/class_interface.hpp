// Contains a C++ interface. Pure virtual.
// Expecting an implementation.

class Simple {
public:
    Simple();
    virtual ~Simple();

    virtual void func1() = 0;
    virtual void operator=(const Simple& other) = 0;

private:
    virtual char* func3() = 0;
};
