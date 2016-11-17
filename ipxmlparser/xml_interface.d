module ipxmlparser;

import std.experimental.xml;
import std.string;
import std.file;
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
    int default_val;
    int startup_val;
}

void getSubTypes(string xml_data) 
{
    auto xml = new DocumentParser(xml_data);
    SubType[] subTypes;
    
    xml.onStartTag["SubType"] = (ElementParser xml)
    {
        XML_SubType subType;
        subType.name = xml.tag.attr["name"];
        subType.unit = xml.tag.attr["unit"];
        subType.type = xml.tag.attr["type"];
        subType.min = xml.tag.attr["min"];
        subType.max = xml.tag.attr["max"];

        xml.parse();
    };

    xml.parse();
}

void main(string[] args) {
    file = args[1];
    string s = cast(string)std.file.read(file);
    check(s);

        auto cursor = 
         chooseLexer!string
        .parser
.cursor(&uselessCallback); // If an index is not well-formed, just tell us but continue parsing

    return;
}