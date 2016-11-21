module ipxmlparser.parser;

import ipxmlparser.token;
import ipxmlparser.element;
import ipxmlparser.tokenqueue;
import ipxmlparser.elementqueue;
import ipxmlparser.attributelist;

class XMLParser
{
public:
    this()
    {
	elementQueue = new XMLElementQueue();
    }

    void ParseTokenQueue(XMLTokenQueue tokenQueue)
    {
	XMLToken token;
	while (tokenQueue.Length() > 0)
	{
	    token = tokenQueue.Pull();
	    if (token.IsTagBegin())
	    {
		ParseTag(tokenQueue);
		continue;
	    }
	    elementQueue.Push(new XMLElement(token.ToString()));
	}
    }

    XMLElementQueue GetElementQueue()
    {
	return elementQueue;
    }

private:
    XMLElementQueue elementQueue;

    void ParseTag(XMLTokenQueue tokenQueue)
    {
	XMLToken token = tokenQueue.Pull();
	if (token.IsForwardSlash())
	{
	    ParseEndTag(tokenQueue);
	}
	else if (token.IsName())
	{
	    ParseBeginTag(tokenQueue, token.ToString());
	}
	else
	{
	    throw new Exception("Start of tag <" ~ token.ToString() ~ " is not valid.");
	}
    }

    void ParseEndTag(XMLTokenQueue tokenQueue)
    {
	XMLToken token = tokenQueue.Pull();
	if (!token.IsName())
	{
	    throw new Exception("End tag expected name, not " ~ token.ToString() ~ ".");
	}

	string name = token.ToString();

	token = tokenQueue.Pull();
	if (!token.IsTagEnd())
	{
	    throw new Exception("Expected end of tag to be >, not " ~ token.ToString() ~ ".");
	}

	elementQueue.Push(new XMLElement(true, name));
    }

    void ParseBeginTag(XMLTokenQueue tokenQueue, string name)
    {
	XMLAttributeList attributeList = new XMLAttributeList();
	bool terminating = false;

	while (true)
	{
	    string attrname;
	    string attrvalue;

	    XMLToken token = tokenQueue.Pull();

	    if (token.IsTagEnd())
	    {
		break;
	    }

	    if (token.IsForwardSlash())
	    {
		token = tokenQueue.Pull();
		if (token.IsTagEnd())
		{
		    terminating = true;
		    break;
		}
		throw new Exception("Expected a > to follow /, not " ~ token.ToString() ~ ".");
	    }

	    if (!token.IsName())
	    {
		throw new Exception("Expected a name, not " ~ token.ToString() ~ ".");
	    }
	    attrname = token.ToString();

	    token = tokenQueue.Pull();
	    if (!token.IsAssignment())
	    {
		throw new Exception("Expected an assignment, not " ~ token.ToString() ~ ".");
	    }

	    token = tokenQueue.Pull();
	    if (!token.IsValue())
	    {
		throw new Exception("Expected a value, not " ~ token.ToString() ~ ".");
	    }
	    attrvalue = token.GetValue();

	    attributeList.Push(attrname, attrvalue);
	}
		
	elementQueue.Push(new XMLElement(name, attributeList, terminating));
    }
}
