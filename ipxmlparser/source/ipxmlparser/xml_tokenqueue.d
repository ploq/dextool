module ipxmlparser.xml_tokenqueue;

import std.algorithm.mutation;

import ipxmlparser.xml_token;

class XMLTokenQueue
{
public:
    this()
    {
	tokenList = new XMLToken[0];
    }

    bool Push(XMLToken t)
    {
	tokenList[tokenList.length++] = t;
	return true;
    }

    XMLToken Pull()
    {
	if (tokenList.length == 0)
	{
	    return new XMLToken("");
	}
    reverse(tokenList);
	XMLToken returnToken = tokenList[tokenList.length-1];
	tokenList.length--;
    reverse(tokenList);
	return returnToken;
    }

    ulong Length()
    {
	return tokenList.length;
    }

private:
    XMLToken[] tokenList;
}
