module b0h.xml.elementqueue;

import b0h.xml.element;
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
	elementList = elementList.reverse;
	XMLElement returnElement = elementList[elementList.length-1];
	elementList.length--;
	elementList = elementList.reverse;
	return returnElement;
    }

    ulong Length()
    {
	return elementList.length;
    }

private:
    XMLElement[] elementList;
}
