module ipxmlparser.document;

import ipxmlparser.attributelist;
import ipxmlparser.node;

class XMLDocument
{
public:
    this()
    {
	root = new XMLNode();
	currentnode = root;
    }

    void OnStartTag(string name, XMLAttributeList params, bool isterminating)
    {
	XMLNode newnode = new XMLNode(name, params, currentnode, isterminating);
	currentnode.AddNode(newnode);
	if (!isterminating)
	{
	    currentnode = newnode;
	}
		
    }

    void OnEndTag(string name)
    {
	if (currentnode.GetParent() !is null)
	{
	    currentnode = currentnode.GetParent();
	}
    }

    void OnText(string text)
    {
	currentnode.AddText(text);
    }

    string ToString()
    {
	string returnstr;
	XMLNode[] childs = root.GetChilds();
	for (ulong i = 0; i < childs.length; ++i)
	{
	    returnstr ~= childs[i].ToString("");
	}
	return returnstr;
    }

    XMLNode GetRoot()
    {
	if (root.GetChilds().length > 0)
	{
	    return root.GetChilds()[0];
	}
	return null;
    }

private:
    XMLNode root;
    XMLNode currentnode;
}
