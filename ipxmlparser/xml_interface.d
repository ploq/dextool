module ipxmlparser.interfaceparser;

import std.stdio;
import std.string;
import std.file;
import std.conv;
import std.container.array;
import std.typecons;

import ipxmlparser.documentbuilder;
import ipxmlparser.document;

import ipxmlparser.fundamentals;

class XML_Interface_Parser
{
public:
    this(string filename)
    {	
	XMLDocumentBuilder builder = new XMLDocumentBuilder();
	XMLDocument xmldoc;
	try
	{
	    xmldoc = builder.Build(filename);
	}
	catch (Exception e)
	{
	    throw new Exception("Could not find file " ~ filename);
	}
    
	auto root = xmldoc.GetRoot();

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
    }

    XML_Interface GetInterface()
    {
	return iface;
    }
private:
    XML_Interface iface;
    string filename;
}

/*void main(string[] args)
{
    XML_Interface_Parser ifaceparser = new XML_Interface_Parser(args[1]);
    auto iface = ifaceparser.GetInterface();

    writeln(iface.name);
    writeln(iface.types);
    foreach (i ; iface.interfaces[0].ditems)
    {
	writeln(i);
    }
    
    return;
}*/
