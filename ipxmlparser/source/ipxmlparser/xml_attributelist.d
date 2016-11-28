module ipxmlparser.xml_attributelist;

import std.container.array;

class XMLAttributeList
{
public:
    this()
    {
	//attributeList = new string[0];
    }

    bool Push(string name, string value)
    {
	attributeList.insertBack(name);
	attributeList.insertBack(value);
	return true;
    }

    Array!string GetAttributeList()
    {
	return attributeList;
    }

    string ToString()
    {
	string returnstr;
	for (ulong i = 0; i < attributeList.length; i += 2)
	{
	    returnstr ~= attributeList[i];
	    returnstr ~= "=\"'";
	    returnstr ~= attributeList[i+1];
	    returnstr ~= "'\" ";
	}
	return returnstr;
    }

    string GetAttribute(string attrname)
    {
	for (ulong i = 0; i < attributeList.length; i += 2)
	{
	    if (attributeList[i] == attrname)
	    {
		return attributeList[i+1];
	    }
	}
	return null;
    }

private:
    Array!string attributeList;
}
 
