module ipxmlparser.xml_elementqueue;

import std.algorithm.mutation;

import ipxmlparser.xml_element;

class XMLElementQueue
{
public:
    this()
    {
	elementList = new XMLElement[0];
    }

    bool Push(XMLElement t)
    {
	elementList[elementList.length++] = t;
	return true;
    }

    XMLElement Pull()
    {
	if (elementList.length == 0)
	{
	    return new XMLElement();
	}
    reverse(elementList);
	XMLElement returnElement = elementList[elementList.length-1];
	elementList.length--;
	reverse(elementList);
	return returnElement;
    }

    ulong Length()
    {
	return elementList.length;
    }

private:
    XMLElement[] elementList;
}
