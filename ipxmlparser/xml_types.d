module ipxmlparser.typesparser;

import std.stdio;
import std.string;
import std.file;
import std.conv;
import std.container.array;
import std.typecons;

import ipxmlparser.documentbuilder;
import ipxmlparser.document;

import ipxmlparser.fundamentals;

class XML_Types_Parser
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

	foreach (type ; root.GetChilds())
	{
	    switch(type.GetName())
	    {
	    case "SubType":
		string tname = type.GetAttribute("name");
		string ttype = type.GetAttribute("type");
		long tmin = to!int(type.GetAttribute("min"));
		long tmax = to!int(type.GetAttribute("max"));
		string tunit = type.GetAttribute("unit");
		types.subTypes.insertBack(XML_SubType(tname, ttype, tmin, tmax, tunit));
		break;
	    case "Record":
		XML_Record record;
		record.name = type.GetAttribute("name");
		foreach (variable ; type.GetChilds())
		{
		    string vname = variable.GetAttribute("name");
		    string vtype = variable.GetAttribute("type");
		    record.vars.insertBack(XML_Variable(vname, vtype));
		}
		types.records.insertBack(record);
		break;
	    case "Enum":
		XML_Enum enumm;
		enumm.name = type.GetAttribute("name");
		foreach (enumitem ; type.GetChilds())
		{
		    string ename = enumitem.GetAttribute("name");
		    long evalue = to!long(enumitem.GetAttribute("value"));
		    enumm.enumitems.insertBack(XML_EnumItem(ename, evalue));
		}
		types.enums.insertBack(enumm);
		break;
	    default:
		break;
	    }
	}
    }

    XML_Types GetTypes()
    {
	return types;
    }
private:
    XML_Types types;
    string filename;
}

void main(string[] args)
{
    XML_Types_Parser typesparser = new XML_Types_Parser(args[1]);
    auto types = typesparser.GetTypes();

    writeln(types.ToString());

    /*writeln(iface.name);
    writeln(iface.types);
    foreach (i ; iface.interfaces[0].ditems)
    {
	writeln(i);
    }*/
}
