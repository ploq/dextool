module ipxmlparser.xml_namespaceparser;

import std.stdio;
import std.string;
import std.file;
import std.conv;
import std.container.array;
import std.typecons;

import ipxmlparser.xml_documentbuilder;
import ipxmlparser.xml_document;

import ipxmlparser.xml_fundamentals;

class XML_Namespace_Parser
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
	namespace.name = root.GetAttribute("name");
    }

    XML_Namespace GetNamespace()
    {
	return namespace;
    }
private:
    XML_Namespace namespace;
    string filename;
}

/*void main(string[] args)
{
    XML_Namespace_Parser namespaceparser = new XML_Namespace_Parser(args[1]);
    auto namespace = namespaceparser.GetNamespace();

    writeln(namespace.ToString());

    /*writeln(iface.name);  
    writeln(iface.types);
    foreach (i ; iface.interfaces[0].ditems)
    {
	writeln(i);
    }
}*/
