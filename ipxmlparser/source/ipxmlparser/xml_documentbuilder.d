module ipxmlparser.xml_documentbuilder;

import ipxmlparser.xml_document;
import ipxmlparser.xml_lexer;
import ipxmlparser.xml_parser;

import std.stdio;

class XMLDocumentBuilder
{
public:
    this()
    {
    }
	
    XMLDocument Build(string filename)
    {
	try
	{
	    XMLLexer lexer = new XMLLexer();
	    if (!lexer.LoadAndParseFile(filename))
	    {
		throw new Exception("Could not build XMLDocument out of " ~ filename);
	    }

	    auto tokenqueue = lexer.GetTokenQueue();

	    XMLParser parser = new XMLParser();
	    parser.ParseTokenQueue(tokenqueue);

	    auto elementqueue = parser.GetElementQueue();

	    XMLDocument returndoc = new XMLDocument();
	    typeof(elementqueue.Pull()) element;
	    while ((element = elementqueue.Pull()).IsValid())
	    {
		if (element.IsStartTag())
		{
		    returndoc.OnStartTag(element.GetName(), element.GetAttributeList(), element.IsTerminating());
		}
		else if (element.IsEndTag())
		{
		    returndoc.OnEndTag(element.GetName());
		}
		else if (element.IsText())
		{
		    returndoc.OnText(element.GetText());
		}
	    }
	    return returndoc;
	}
	catch (Exception e)
	{
	    writeln(e.msg);
	    throw new Exception("Could not build XMLDocument out of " ~ filename);
	}
    }	

private:
}
