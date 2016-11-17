module b0h.xml.element;

import b0h.xml.attributelist;

import std.stdio;

class XMLElement
{
public:
    this()
    {
	attributeList = new XMLAttributeList();
	name = "";
	textcontent = "";
	tag_end = false;
	tag_start = false;
	tag_text = false;
	terminating = false;
    }

    this(string name, XMLAttributeList attrList, bool terminating)
    {
	this();
	tag_start = true;
	this.name = name;
	this.attributeList = attrList;
	this.terminating = terminating;
    }

    this(bool isEndTag, string name)
    {
	this();
	tag_end = true;
	this.name = name;
    }

    this(string textcontent)
    {
	this();
	tag_text = true;
	this.textcontent = textcontent;
    }

    string ToString()
    {
	string returnstr;
	if (tag_start)
	{
	    returnstr ~= "<" ~ name ~ " ";
	    returnstr ~= attributeList.ToString();
	    if (terminating)
	    {
		returnstr ~= "/";
	    }
	    returnstr ~= ">";
	}
	else if (tag_end)
	{
	    returnstr ~= "</" ~ name ~ ">";
	}
	else if (tag_text)
	{
	    returnstr ~= textcontent;
	}
	return returnstr;
    }

    bool IsValid()
    {
	return tag_end || tag_start || tag_text;
    }

    bool IsStartTag()
    {
	return tag_start;
    }

    bool IsEndTag()
    {
	return tag_end;
    }

    bool IsText()
    {
	return tag_text;
    }

    string GetText()
    {
	return textcontent;
    }

    string GetName()
    {
	return name;
    }

    XMLAttributeList GetAttributeList()
    {
	return attributeList;
    }

    bool IsTerminating()
    {
	return terminating;
    }
private:
    XMLAttributeList attributeList;
    string name;
    string textcontent;
    bool tag_end;
    bool tag_start;
    bool tag_text;
    bool terminating;
}
