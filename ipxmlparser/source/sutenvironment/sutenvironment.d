module sutenvironment.sutenvironment;

import ipxmlparser.xml_fundamentals;
import ipxmlparser.xml_types;
import ipxmlparser.xml_interface;

import ipxmlparser.xml_documentbuilder;

import std.container.array;
import std.file;
import std.string;
import std.stdio;

struct SUTEnv
{
    XML_Interface iface;
    XML_Types types;

    string ToString()
    {
	string returnstr;
	returnstr ~= iface.ToString() ~ "\n\n" ~ types.ToString();
	return returnstr;
    }
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

    SUTEnv GetTypeFromNamespace(string namespace, string datatype)
    {
	return SUTEnv();
    }

    string ToString()
    {
	string returnstr;
	foreach (entry; map.keys)
	{
	    returnstr ~= entry ~ ": \n" ~ map[entry].ToString() ~ "\n\n\n\n\n";
	}
	return returnstr;
    }

private:
    SUTEnv[string] map;

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
	map[folder] = SUTEnv();
	foreach (file ; files)
	{
	    if (indexOf(file, "types.xml") != -1)
	    {
		XML_Types_Parser parser = new XML_Types_Parser(file);
		map[folder].types = parser.GetTypes();
	    }
	    else if (indexOf(file, "namespace.xml") == -1)
	    {
		XML_Interface_Parser parser = new XML_Interface_Parser(file);
		auto iface = parser.GetInterface();
		map[folder ~ "/" ~ iface.name] = SUTEnv(iface);
	    }
	}
    }
}


void main(string[] args)
{
    SUTEnvironment se = new SUTEnvironment();
    se.Build("namespaces");
    writeln(se.ToString());
}
