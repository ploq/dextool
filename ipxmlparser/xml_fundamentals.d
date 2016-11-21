module ipxmlparser.fundamentals;

import std.container.array;
import std.typecons;

struct XML_Interface
{
    string name;
    XML_Types types;
    Array!XML_ContInterface interfaces;
}

struct XML_ContInterface 
{
    string name;
    string direction;
    Array!XML_DataItem ditems;
}

struct XML_Types
{
    Array!XML_SubType subTypes;
    Array!XML_Enum enums;
    Array!XML_Record records;
}

struct XML_SubType
{
    string name;
    string type;
    long min;
    long max;
    string unit;
}

struct XML_Enum
{
    Array!(Tuple!(string, Array!int)) values;
}

struct XML_Record
{
    Array!XML_Variable vars;
}

struct XML_Variable
{
    string name;
    int value;
}

struct XML_DataItem 
{
    string name;
    string type;
    string default_val;
    string startup_val;
}
