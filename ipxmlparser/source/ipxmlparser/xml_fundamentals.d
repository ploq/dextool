module ipxmlparser.xml_fundamentals;

import std.container.array;
import std.typecons;
import std.conv;

struct XML_Interface
{
    string name;
    XML_Types types;
    Array!XML_ContInterface interfaces;

    string ToString()
    {
	string returnstr;
	returnstr ~= "XML_Interface:[name=" ~ name ~ ", types=" ~ types.ToString() ~ ", interfaces=[\n";
	foreach (i ; interfaces)
	{
	    returnstr ~= i.ToString() ~ ",\n";
	}
	returnstr ~= "]]";
	return returnstr;
    }
}

struct XML_ContInterface 
{
    string name;
    string direction;
    Array!XML_DataItem ditems;

    string ToString()
    {
	string returnstr;
	returnstr ~= "XML_ContInterace:[name=" ~ name ~ ", direction=" ~ direction ~ ", ditems=[\n";
	foreach (d ; ditems)
	{
	    returnstr ~= d.ToString() ~ ",\n";
	}
	returnstr ~= "]]";
	return returnstr;
    }
}

struct XML_Types
{
    Array!XML_SubType subTypes;
    Array!XML_Enum enums;
    Array!XML_Record records;
    
    string ToString()
    {
	string returnstr;
	returnstr ~= "XML_Types:[subTypes=[\n";
	foreach (s ; subTypes)
	{
	    returnstr ~= s.ToString() ~ ",\n";
	}
	returnstr ~= "], enums=[\n";
	foreach (e ; enums)
	{
	    returnstr ~= e.ToString() ~ ",\n";
	}
	returnstr ~= "], records=[\n";
	foreach (r ; records)
	{
	    returnstr ~= r.ToString() ~ ",\n";
	}
	returnstr ~= "]]";
	return returnstr;
    }
}

struct XML_SubType
{
    string name;
    string type;
    long min;
    long max;
    string unit;

    string ToString()
    {
	return "XML_SubType:[name=" ~ name ~ ", type=" ~ type ~ ", min=" ~ text(min) ~ ", max=" ~ text(max) ~ ", unit=" ~ unit ~ "]";
    }
}

struct XML_Enum
{
    string name;
    Array!XML_EnumItem enumitems;

    string ToString()
    {
	string returnstr;
	returnstr ~= "XML_Enum:[name=" ~ name ~ ", enumitems=[\n";
	foreach (e ; enumitems)
	{
	    returnstr ~= e.ToString() ~ ",\n";
	}
	returnstr ~= "]]";
	return returnstr;
    }
}

struct XML_EnumItem
{
    string name;
    long value;
    
    string ToString()
    {
	return "XML_EnumItem:[name=" ~ name ~ ", value=" ~ text(value) ~ "]";
    }
}

struct XML_Record
{
    string name;
    Array!XML_Variable vars;

    string ToString()
    {
	string returnstr;
	returnstr ~= "XML_Record:[name=" ~ name ~ ", vars=[\n";
	foreach (var ; vars)
	{
	    returnstr ~= var.ToString() ~ ",\n";
	}
	returnstr ~= "]]";
	return returnstr;
    }
}

struct XML_Variable
{
    string name;
    string type;

    string ToString()
    {
	return "XML_Variable:[name=" ~ name ~ ", type=" ~ type ~ "]";
    }
}

struct XML_DataItem 
{
    string name;
    string type;
    string default_val;
    string startup_val;

    string ToString()
    {
	return "XML_DataItem:[name=" ~ name ~ ", type=" ~ type ~ ", default_val=" ~ default_val ~ ", startup_val=" ~ startup_val ~ "]";
    }
}
