module ipxmlparser;

import std.stdio;
import std.string;
import std.file;
import std.conv;
import std.container.array;
import std.typecons;

import b0h.xml.documentbuilder;
import b0h.xml.document;

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

void getSubTypes(string xml_data) 
{
    /*auto xml = new DocumentParser(xml_data);
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

    xml.parse();*/
}

void main(string[] args)
{
    XMLDocumentBuilder builder = new XMLDocumentBuilder();
    XMLDocument xmldoc;
    try
    {
	xmldoc = builder.Build(args[1]);
    }
    catch (Exception e)
    {
	writeln("Could not find file " ~ args[1]);
    }
    
    auto root = xmldoc.GetRoot();

    switch(root.GetName())
    {
    case "Interface":
	XML_Interface iface;
	iface.name = root.GetAttribute("name");
	auto ifacetypes = root.SearchFirstChild("Types");
	foreach (type ; ifacetypes.GetChilds())
	{
	    switch(type.GetName())
	    {
	    case "SubType":
		string tname = type.GetAttribute("name");
		string ttype = type.GetAttribute("type");
		long tmin = to!int(type.GetAttribute("min"));
		long tmax = to!int(type.GetAttribute("max"));
		string tunit = type.GetAttribute("unit");
		iface.types.subTypes.insertBack(XML_SubType(tname, ttype, tmin, tmax, tunit));
		break;
	    default:
		break;
	    }
	}

	auto cifaces = root.SearchChilds("ContinuesInterface");
	foreach (ciface ; cifaces)
	{
	    string ciname = ciface.GetAttribute("name");
	    string cidirection = ciface.GetAttribute("direction");
	    iface.interfaces.insertBack(XML_ContInterface(ciname, cidirection, Array!XML_DataItem()));
	    
	    auto dataitems = ciface.SearchChilds("DataItem");
	    foreach (dataitem ; dataitems)
	    {
		string dname = dataitem.GetAttribute("name");
		string dtype = dataitem.GetAttribute("type");
		string dstartup = dataitem.GetAttribute("startupValue");
		string ddefault = dataitem.GetAttribute("defaultValue");
		iface.interfaces.back().ditems.insertBack(XML_DataItem(dname, dtype, dstartup, ddefault));
	    }
	}

	writeln(iface.name);
	writeln(iface.types);
	foreach (i ; iface.interfaces[0].ditems)
	{
	    writeln(i);
	}

	break;
    default:
	writeln("NEJ");
	break;
    }
    
    return;
}

/*struct XML_DataItem 
{
    string name;
    string type;
    str default_val;
    str startup_val;
    }*/
