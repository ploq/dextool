module sutenvironment.sutenvironment;

import ipxmlparser.xml_fundamentals;
import ipxmlparser.xml_interfaceparser;

import std.container.array;
import std.file;
import std.string;
import std.stdio;

struct SUTSubEnv
{
    XML_Interface iface;
    XML_Types types;
}

class SUTEnvironment
{
public:
    this()
    {
    }

    bool Build(string folder)
    {
	foreach (subfolder ; GetSubFolders(folder))
	{
	    ParseFiles(subfolder, GetFiles(subfolder));
	}
	return true;
    }

    SUTSubEnv GetTypeFromNamespace(string namespace, string datatype)
    {
	return SUTSubEnv();
    }

    string ToString()
    {
	return "SUT";
    }

    /*bool Build(string folder)
    {
	foreach (namespace ; FindFile("namespace.xml", folder))
	{
	    XML_Namespace_Parser namespaceParser = new XML_Namespace_Parser(namespace);
	    xml_namespaces.insertBack(namespaceParser.GetNamespace());
	}
	/*foreach (entry ; dirEntries(folder, SpanMode.depth))
	{
	    writeln(entry);
	    }*
	return true;
    }*/

private:
    /*Array!string FindFile(string filename, string folder)
    {
	Array!string returnarray;
	foreach (entry ; dirEntries(folder, SpanMode.depth))
	{
	    if (indexOf(entry, "/" ~ filename) != -1)
	    {
		returnarray.insertBack(entry);
	    }
	}
	return returnarray;
    }*/

    

    Array!string GetSubFolders(string folder)
    {
	Array!string returnarray;
	foreach (entry ; dirEntries(folder, SpanMode.depth))
	{
	    if (entry.isDir)
	    {
		returnarray.insertBack(entry);
	    }
	}
	return returnarray;
    }

    Array!string GetFiles(string folder)
    {
	Array!string returnarray;
	foreach (entry ; dirEntries(folder, "*.xml", SpanMode.shallow))
	{
	    if (entry.isFile)
	    {
		returnarray.insertBack(entry);
	    }
	}
	return returnarray;
    }

    void ParseFiles(string folder, Array!string files)
    {
	foreach (file ; files)
	{
	    SUTSubEnv sss;
//	    sss.
	}
    }
}


void main(string[] args)
{
    import std.stdio;

    SUTEnvironment se = new SUTEnvironment();
    se.Build("namespaces");
    writeln(se.ToString());
}
