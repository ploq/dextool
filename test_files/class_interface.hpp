class Simple {
public:
    Simple();
    ~Simple();

    void operator=(const Simple& other) = 0;
    virtual void func1() = 0;

private:
    virtual char* func3() = 0;
};
