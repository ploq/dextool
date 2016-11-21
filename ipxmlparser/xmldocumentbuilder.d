module ipxmlparser.documentbuilder;

import ipxmlparser.document;
import ipxmlparser.lexer;
import ipxmlparser.parser;

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
		return null;
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
	    throw new Exception("Could not build XMLDocument out of " ~ filename);
	    return null;
	}
    }	

private:
}
