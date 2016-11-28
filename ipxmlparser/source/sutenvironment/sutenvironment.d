module sutenvironment.sutenvironment;

import ipxmlparser.xml_fundamentals;
import ipxmlparser.xml_types;
import ipxmlparser.xml_interface;

import std.container.array;
import std.file;
import std.string;
import std.stdio;
import std.conv;
import std.path;

struct SUTEnv
{
    XML_Interface iface;
    XML_Types types;

    bool valid;
    bool hasinterface;
    bool hastypes;

    string ToString()
    {
	string returnstr;
	returnstr ~= iface.ToString() ~ "\n\n" ~ types.ToString();
	return returnstr;
    }
}

@safe class SUTEnvironment
{
public:
    this()
    {
    }

    @trusted bool Build(string folder)
    {
	folder = buildNormalizedPath(folder);
		foreach (subfolder ; GetSubFolders(folder))
		{
			ParseFiles(subfolder, GetFiles(subfolder));
		}
		return true;
	}


    @trusted SUTEnv GetSUTFromNamespace(string namespace)
    {
	import std.algorithm: canFind;

	if (map.keys.canFind(namespace))
	{
	    return map[namespace];
	}
	SUTEnv env;
	env.valid = false;
	return env;
    }

    @trusted string ToString()
    {
		string returnstr;
		foreach (entry; map.keys)
		{
			returnstr ~= entry ~ ": \n" ~ map[entry].ToString() ~ "\n\n\n\n\n";
		}
		return returnstr;
    }

    @trusted string[] GetSUTList()
    {
		return map.keys;
    }

private:
    SUTEnv[string] map;

    @trusted Array!string GetSubFolders(string folder)
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

    @trusted Array!string GetFiles(string folder)
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

    @trusted void ParseFiles(string folder, Array!string files)
    {
		string key = chompPrefix(folder, "namespaces/");
		key = replace(key, "/", "::");
		key = capitalize(key);

		auto prev = key[0];
		for (long i = 1; i < key.length; ++i)
		{
			if (prev == ':' && key[i] != ':')
			{
			cast(char)key[i] = capitalize(text(key[i]))[0];
			}
			cast(char)prev = key[i];
		}

		map[key] = SUTEnv();
		map[key].valid = false;
		foreach (file ; files)
		{
			if (indexOf(file, "types.xml") != -1)
			{
			XML_Types_Parser parser = new XML_Types_Parser(file);
			map[key].types = parser.GetTypes();
			map[key].valid = true;
			map[key].hastypes = true;
			map[key].hasinterface = false;
			}
			else if (indexOf(file, "namespace.xml") == -1)
			{
			XML_Interface_Parser parser = new XML_Interface_Parser(file);
			auto iface = parser.GetInterface();
			string newkey = key ~ "::" ~ iface.name;
			map[newkey] = SUTEnv(iface);
			map[newkey].valid = true;
			map[newkey].hasinterface = true;
			map[newkey].hastypes = false;
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
