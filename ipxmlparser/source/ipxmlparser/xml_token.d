module ipxmlparser.xml_token;

import std.stdio;
import std.string;
import std.uni;
import std.conv;

class XMLToken
{
public:
    this(string str)
    {
	token = str;
    }

    string ToString()
    {
	return token;
    }

    string GetValue()
    {
	string returnvalue = token;
	if (IsValue())
	{
	    returnvalue = chop(returnvalue);
	    returnvalue = chompPrefix(returnvalue, text(returnvalue[0]));
	}
	return returnvalue;
    }

    bool IsValid()
    {
	return token != "";
    }

    bool IsTagBegin()
    {
	return token == "<";
    }

    bool IsTagEnd()
    {
	return token == ">";
    }

    bool IsForwardSlash()
    {
	return token == "/";
    }

    bool IsAssignment()
    {
	return token == "=";
    }

    bool IsValue()
    {
	return token.length > 1 && (token[0] == '"' || token[0] == '\'');
    }

    bool IsName()
    {
	return token.length > 0 && (token[0] == '_' || isAlpha(token[0]));
    }

    bool IsText() //TODO: Add more token info
    {
	return token.length > 0;
    }

private:
    string token;
}
