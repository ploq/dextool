module ipxmlparser.tokenqueue;

import ipxmlparser.token;

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
	tokenList = tokenList.reverse;
	XMLToken returnToken = tokenList[tokenList.length-1];
	tokenList.length--;
	tokenList = tokenList.reverse;
	return returnToken;
    }

    ulong Length()
    {
	return tokenList.length;
    }

private:
    XMLToken[] tokenList;
}
