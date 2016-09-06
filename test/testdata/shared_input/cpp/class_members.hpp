#ifndef CLASS_MEMBERS_HPP
#define CLASS_MEMBERS_HPP

class Forward_ptr;
class Forward_ref;

class ToForward {
    Forward_ptr* fwd_ptr;
    Forward_ref& fwd_ref;
};

class Impl {
};

class Impl_ptr {
};

class Impl_ref {
};

class ToImpl {
    Impl impl;
    Impl_ptr* impl_ptr;
    Impl_ref& impl_ref;
};

class ToPrimitive {
    // ignoring primitive type
    int x;
};
#endif // CLASS_MEMBERS_HPP
