module ipxmlparser.xml_lexer;

import ipxmlparser.xml_token;
import ipxmlparser.xml_tokenqueue;

import std.stdio;
import std.uni;
import std.conv;

class XMLLexer //TODO: Support for comments
{
public:
    this()
    {
	tokenQueue = new XMLTokenQueue();
    }

    bool LoadAndParseFile(string filename)
    {
	string xmlstring;
	try
	{
	    File xmlfile = File(filename, "r");
	    while (!xmlfile.eof())
	    {
		xmlstring ~= xmlfile.readln();
	    }
	    xmlfile.close();
	}
	catch(Exception e)
	{
	    return false;
	}
		
	FillTokenQueue(xmlstring);	
		
	return true;
    }

    XMLTokenQueue GetTokenQueue()
    {
	return tokenQueue;
    }

private:
    XMLTokenQueue tokenQueue;

    void FillTokenQueue(string xmltext) //TODO: Code better
    {
	bool citations = false;
	bool insidetag = false;
	string currentelement;
	string currentcitation;

	for (ulong i = 0; i < xmltext.length; ++i)
	{
	    auto c = xmltext[i];
	    if (citations)
	    {
		if (text(c) != currentcitation)
		{
		    currentelement ~= c;
		    continue;
		}
		else
		{
		    citations = false;
		    tokenQueue.Push(new XMLToken(currentcitation ~ currentelement ~ currentcitation));
		    currentcitation = "";
		    currentelement = "";
		    continue;
		}
	    }
	    if (insidetag && (c == '"' || c == '\''))
	    {
		citations = true;
		currentcitation = text(c);
		continue;
	    }
	    if (insidetag && isWhite(c) && !citations)
	    {
		if (currentelement.length > 0)
		{
		    tokenQueue.Push(new XMLToken(currentelement));
		    currentelement = "";
		}
		continue;
	    }
	    if (!insidetag && c == '<')
	    {
		if (currentelement.length > 0)
		{
		    tokenQueue.Push(new XMLToken(currentelement));
		    currentelement = "";
		}
		insidetag = true;
		tokenQueue.Push(new XMLToken(text(c)));
		continue;
	    }
	    if (insidetag && c == '>')
	    {
		if (currentelement.length > 0)
		{
		    tokenQueue.Push(new XMLToken(currentelement));
		    currentelement = "";
		}
		insidetag = false;
		tokenQueue.Push(new XMLToken(text(c)));
		continue;
	    }
	    if (insidetag && c == '=' || c == '/' || c == '!' || c == '-')
	    {
		if (currentelement.length > 0)
		{
		    tokenQueue.Push(new XMLToken(currentelement));
		    currentelement = "";
		}
		tokenQueue.Push(new XMLToken(text(c)));
		continue;
	    }
	    currentelement ~= c;
	}
    }
}
