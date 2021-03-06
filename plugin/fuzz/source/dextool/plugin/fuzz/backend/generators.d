module backend.fuzz.generators;

import std.container.array;
import std.typecons;
import logger = std.experimental.logger;


import cpptooling.data.type;
import cpptooling.data.representation;

import dsrcgen.cpp;
import dsrcgen.c;

import xml_parse;
import backend.fuzz.types;

@trusted void generateMainFunc(CppModule main_inner, string app_name) {
    with(main_inner.func_body("int", "main", "int argc, char** argv")) {
        with(if_("!TestingEnvironment::init()")) {
            return_("0");
        }

        stmt(app_name ~ "_Initialize()");
        with(for_("int n = 0", "n < TestingEnvironment::getCycles()", "n++")) {
            with(switch_("TestingEnvironment::getRandType()")) {
                with(case_("RANDOM_GENERATOR")) {
                    stmt("PortStorage::Regenerate()");
                    stmt("break");
                }
                with(case_("STATIC_GENERATOR")) {
                    stmt("TestingEnvironment::readConfig()");
                    stmt("PortStorage::Regenerate(TestingEnvironment::getConfig(), n)");
                    stmt("break");
                }

                with(default_) {
                    stmt("PortStorage::Regenerate()");
                    stmt("break");
                }
            
            }

            stmt(app_name~"_Execute()");
        }

        //stmt(app_name ~ "_Terminate()");
        stmt("PortStorage::CleanUp()");

        return_("0");
    }
}

@trusted void generateMainHdr(CppModule main_hdr_inner, string app_name) {
    ///>>>
    main_hdr_inner.include("fuzz_out/testingenvironment.hpp");
    main_hdr_inner.include("fuzz_out/portenvironment.hpp");
    main_hdr_inner.include(app_name ~ "_main.hpp");
    main_hdr_inner.include("<iostream>");
    main_hdr_inner.include("<map>");
    main_hdr_inner.include("<string>");

    with (main_hdr_inner.enum_) {
        enum_const("RANDOM_GENERATOR");
        enum_const("STATIC_GENERATOR");
    }
}

@trusted void generateCreateInstance(CppModule inner, string return_type, string func_name, 
             string paramType, string paramName, Array!nsclass classes) {
    string port_name = "";
    string port_implname = "";
    string compif_name = "";
    string compif_implname = "";
    foreach(nss ; classes) {
        if (nss.isPort) {
            port_name = nss.name;
            port_implname = nss.impl_name;
        } else {
            compif_name = nss.name;
            compif_implname = nss.impl_name;
        }
    }

    assert(port_name.length != 0);
    assert(port_implname.length != 0);
    assert(compif_name.length != 0);
    assert(compif_implname.length != 0);

    with(inner.func_body(return_type, func_name, paramType ~ " " ~ paramName)) {
        if (paramType[$-1] == '&') {
            paramType = paramType[0..$-1]; //Remove reference
        }
    ///>>>
	return_(E(Et("PortEnvironment::createPort")(compif_implname, port_name, port_implname, paramType))(paramName ~ ", " ~ paramName));
    }
}

@trusted nsclass generateClass(CppModule main_hdr_inner, CppModule inner, string class_name,
			       const CppNsStack fqn_ns, Namespace ns, ImplData data, CppClass class_, xml_parse xmlp) {
    //Some assumptions are made. Does all providers and requirers end with Requirer or Provider?
    import std.array;
    import std.string : toLower, indexOf;
    import std.algorithm : endsWith;

    auto inner_class = inner.class_(class_name ~ "_Impl", "public " ~ class_name);
    nsclass sclass = nsclass(false, inner_class, class_name, class_name ~ "_Impl");

    
    final switch(data.lookup(class_.id)) with (Kind) {
        case none:
            sclass.isPort = true;
            generatePortClass(main_hdr_inner, inner_class, class_name, ns, fqn_ns, xmlp);
            break;
        case ContinousInterface:
            generateCompIfaceClass(inner_class, class_name, ns);
            break;
        }
    return sclass;
}
@trusted CppModule generateCompIfaceClass(CppModule inner_class, string class_name, Namespace ns) {
    import std.array;
    import std.string : toLower, indexOf;
    import std.algorithm : endsWith;

    logger.info("Generating component interface class: " ~ class_name);
    string port_name = class_name;
    if (class_name.endsWith("Requirer")) {
        port_name = class_name[0..$-("_Requirer".length)];
    } else if (class_name.endsWith("Provider")) {
        port_name = class_name[0..$-("_Provider".length)];
    }

    with (inner_class) {
        with (private_) {
            logger.trace("class_name: " ~ class_name);

            stmt(E(port_name ~ "* port"));
        }
        with (public_) {
            with (func_body("", class_name ~ "_Impl")) { //Generate constructor
            }
            
            with (func_body("", class_name ~ "_Impl", port_name ~ "* p")) {
                stmt(E("port") = E("p"));
            }

            with(func_body(port_name~"_Impl*", "Get_Port_Impl")) {
                return_(E(Et("static_cast")(port_name ~ "_Impl*"))("port"));
            }
        }
    }
    return inner_class;
}

@trusted CppModule generatePortClass(CppModule main_hdr_inner, CppModule inner_class, string class_name,
				     Namespace ns, const CppNsStack fqn_ns, xml_parse xmlp) {
    import std.array : empty, join, array;
    import std.string : toLower, indexOf, capitalize;
    import std.algorithm : endsWith;
    import std.format : format;

    with(main_hdr_inner) {
        foreach (ciface; ns.interfaces.ci) {
        ///>>>
            stmt(E(format("%s::%sT %s", fqn_ns.array[0..$-1].join("::"), ciface.name, ciface.name.toLower)));
        } 

        foreach (eiface; ns.interfaces.ei) {
        ///>>>
            foreach(event ; eiface.events) {
                stmt(E(format("%s::%sT %s", fqn_ns.array[0..$-1].join("::"), event.name, event.name.toLower)));
            } 
        } 
    }


    logger.info("Generating port class: " ~ class_name);
    with (inner_class) {
        with (private_) {
            logger.trace("class_name: " ~ class_name);
            logger.trace("generateClass fqn_ns: " ~ fqn_ns.array.join("::"));
            stmt(E("RandomGenerator* randomGenerator"));
            stmt(Et("std::vector")("std::string") ~ E("clients"));
            stmt(E("std::string name"));
            stmt(E(class_name ~ "*") ~ E("other"));
        }
        
        with (public_) {
            with (func_body("", class_name ~ "_Impl", "std::string n")) { //Generate constructor
		        string expr = format(`%s::%s()`, "&TestingEnvironment", "createRandomGenerator");
                stmt(E("randomGenerator") = E(expr));
                stmt(E("name") = E("n"));
                stmt(E("randomGenerator->generateClients")("clients, 1024"));
                stmt(E("other") = E("0"));
            }
            
            with (func_body("", "~" ~ class_name ~ "_Impl")) { /* Generate destructor */ }
            with(func_body(class_name, "Get_Other_End")) {
                return_("other");
            }

            with(func_body("std::string", "getName")) {
                return_("name");
            }

            with(method_inline(No.isVirtual, "void", "Set_Other_End", No.isConst, class_name~"* other_end")) {
                stmt(E("other") = E(Et("static_cast")(class_name ~ "_Impl*"))("other_end"));

            }
            auto func2 = func_body("void", "Regenerate");
            auto func1 = func_body("void", "Regenerate",
                                     "const std::map<std::string, std::vector<std::vector<int> > > &vars, const int64_t & curr_cycles"); 

	        foreach (ciface; ns.interfaces.ci) {
		        foreach (ditem; ciface.data_items) {
                            string arr = xmlp.isArray(ditem, ns.name);
                            string[string] minmax;
                            if (arr.length > 0) {
                                minmax = xmlp.findMinMax(ns.name, arr, ditem);
                            } else {
                                minmax = xmlp.findMinMax(ns.name, ditem.type, ditem);
                            }
		            
		            if (minmax.length > 0) {
                                string defVal = minmax["defVal"];
			                    string min = minmax["min"];
                                string max = minmax["max"];
                                string type_type = minmax["type"];
                                string type_ns = minmax["namespace"];
			    
                                switch (type_type) {
                                    case "SubType":
                                        generateSubType(func1, func2, ciface.name, ditem.name, min, max, defVal, arr.length > 0);
                                        break;
                                    case "Enum":
                                        generateEnum(func1, func2, ciface.name, ditem.name, type_ns, ditem.type, min, max);
                                        break;
                                    case "Record":			
                                        generateRecord(func1, func2, ciface.name, ditem.name, ns.name, type_ns, ditem.type, xmlp);
                                        break;
                                    default:
                                        break;
                                    }
                                } else {
                                    string expr1, expr2;
                                    string var = format("%s.%s", ciface.name.toLower, ditem.name);

                                    if(ditem.defaultVal.length != 0) {
                                        expr1 = ditem.defaultVal;
                                        expr2 = ditem.defaultVal;
                                    } else {
                                        expr1 = format(`randomGenerator->generate(%s, "%s.%s", %s)`, "vars", 
                                                                                                    ciface.name.toLower, ditem.name,
                                                                                                    "curr_cycles");
                                        expr2 = `randomGenerator->generate()`;
                                    }
                                    with (func1) { stmt(E(var) = E(expr1)); }
                                    with (func2) { stmt(E(var) = E(expr2)); }
                                }
                            }
		        }   
                foreach(eiface; ns.interfaces.ei) {
                    foreach(event; eiface.events) {
                        generateEvent(func1, func2, event, eiface.name, xmlp, ns);
                    }
                }  
        }
        
    
            //TODO: How to do regenerate for Events?!
            
            with (func_body("std::string", "getNamespace")) {
                return_(format(`"%s"`, fqn_ns.array.join("::")));
            }    
        }
    return inner_class;
}

@trusted void generateSubType(CppModule func1, CppModule func2, string ciface_name, string ditem_name, string min, string max, string defVal, bool isArray) {
    import std.format : format;
    import std.string : toLower;

    string var = format("%s.%s", ciface_name.toLower, ditem_name);
    string expr1, expr2;

    if (isArray) {
        if (defVal.length == 0) {
            string rand_expr1 = format(`i = randomGenerator->generate(%s, "%s.%s", %s, %s, %s)`, "vars", ciface_name.toLower,
                                                                                    ditem_name, min, max, "curr_cycles");
            string rand_expr2 = format(`i = randomGenerator->generate(%s, %s)`, min, max);
            expr1 = format("for(auto &i : %s.%s)\n\t%s", ciface_name.toLower, ditem_name, rand_expr1);
            expr2 = format("for(auto &i : %s.%s)\n\t%s", ciface_name.toLower, ditem_name, rand_expr2);

            with(func1) { stmt(expr1); }
            with(func2) { stmt(expr2); }
        } else {
            expr1 = format("for(auto &i : %s.%s)\n\t%s", ciface_name.toLower, ditem_name, "i = " ~ defVal);
            expr2 = format("for(auto &i : %s.%s)\n\t%s", ciface_name.toLower, ditem_name, "i = " ~ defVal);
            
            with(func1) { stmt(expr1); }
            with(func2) { stmt(expr2); }
        }
    } else {
        if (defVal.length == 0) {
            expr1 = format(`randomGenerator->generate(%s, "%s.%s", %s, %s, %s)`, "vars", ciface_name.toLower,
                                                                                    ditem_name, min, max, "curr_cycles");
            expr2 = format(`randomGenerator->generate(%s, %s)`, min, max);
        } else {
            expr1 = defVal;
            expr2 = defVal;
        }

        with (func1) { stmt(E(var) = E(expr1)); }
        with (func2) { stmt(E(var) = E(expr2)); }

    }
}

@trusted void generateEvent(CppModule func1, CppModule func2, Event event, string eiface_name, xml_parse xmlp, Namespace ns) {
    import std.format : format;
    import std.string : toLower;
    import std.algorithm : joiner;
    import std.conv : to; 

    string func_name = "Get_Other_End()->" ~ event.name ~ "_Event";
    string[] params1, params2;
    string expr1, expr2;
    //lookup min, max for all ditems in event;
    foreach(ditem ; event.data_items) {
        string arr = xmlp.isArray(ditem, ns.name);
        string[string] minmax;
        if (arr.length > 0) {
            minmax = xmlp.findMinMax(ns.name, arr, ditem);
        } else {
            minmax = xmlp.findMinMax(ns.name, ditem.type, ditem);
        }

        if (minmax.length > 0) {
            string min = minmax["min"];
            string max = minmax["max"];
            string defVal = minmax["defVal"];
            string ns_type = minmax["namespace"];
            string type_type = minmax["type"];
            if (defVal.length > 0) {
                params1 ~= defVal;
                params2 ~= defVal;
            } else {
                if (type_type == "Enum") {
                    ///>>>
                    string var = format("%s.%s", event.name.toLower, ditem.name);
                    string fqns_type = format("%s::%sT::Enum", ns_type, ditem.type);
                    expr1 = format(`randomGenerator->generate(%s, "%s.%s", %s, %s, %s)`, "vars", 
                                                                                event.name.toLower,
                                                                                ditem.name, min, max, "curr_cycles");
                    expr2 = format(`randomGenerator->generate(%s, %s)`, min, max);
                    params1 ~= E(Et("static_cast")(fqns_type))(expr1).toString;
                    params2 ~= E(Et("static_cast")(fqns_type))(expr2).toString;
                } else {
                    params2 ~= format("randomGenerator->generate(%s, %s)", min, max);
                    params1 ~= format(`randomGenerator->generate(%s, "%s.%s", %s, %s, %s)`, "vars", event.name.toLower, ditem.name, min, max, "curr_cycles");
                }
            }
        } else {
            params2 ~= "randomGenerator->generate()";
            params1 ~= format(`randomGenerator->generate(%s, "%s.%s", %s)`, "vars", event.name.toLower, ditem.name, "curr_cycles");
        }
    }

    expr1 = func_name ~ "(" ~ to!string(params1.joiner(", ")) ~ ")";
    expr2 = func_name ~ "(" ~ to!string(params2.joiner(", ")) ~ ")";
    with(func1.if_("other")) { stmt(expr1); } 
    with(func2.if_("other")) { stmt(expr2); } 
}

@trusted void generateEnum(CppModule func1, CppModule func2, string ciface_name, string ditem_name, string type_ns,
			   string ditem_type, string min, string max) { 
    import std.format : format;
    import std.string : toLower, capitalize;

    ///>>>
    string var = format("%s.%s", ciface_name.toLower, ditem_name);
    string fqns_type = format("%s::%sT::Enum", type_ns, ditem_type);
    string expr1 = format(`randomGenerator->generate(%s, "%s.%s", %s, %s, %s)`, "vars", 
                                                                                ciface_name.toLower,
                                                                                ditem_name, min, max, "curr_cycles");
    string expr2 = format(`randomGenerator->generate(%s, %s)`, min, max);
    with (func1) { stmt(E(var) = E(Et("static_cast")(fqns_type))(expr1)); }
    with (func2) { stmt(E(var) = E(Et("static_cast")(fqns_type))(expr2)); }
}

@trusted void generateRecord(CppModule func1, CppModule func2, string ciface_name, string ditem_name, string ns_name,
		    string type_ns, string ditem_type, xml_parse xmlp) { 
    import std.format : format;
    import std.string : toLower;

    Variable[string] vars = xmlp.findVariables(type_ns, ditem_type);
    foreach (var_name ; vars) {
        string var = format("%s.%s.%s", ciface_name.toLower, ditem_name, var_name.name);
        if(var_name.defaultVal.length != 0) {
            with (func1) { stmt(E(var) = E(var_name.defaultVal)); }
            with (func2) { stmt(E(var) = E(var_name.defaultVal)); }
            return;
        }
        else if (var_name.min.length != 0 && var_name.max.length != 0) {
            string expr1 = format(`randomGenerator->generate(%s, "%s.%s.%s", %s, %s, %s)`, "vars", 
                                                                                ciface_name.toLower,
                                                                                ditem_name,
                                                                                var_name.name,
                                                                                var_name.min,
                                                                                var_name.max,
                                                                                "curr_cycles");
            string expr2 = format(`randomGenerator->generate(%s, %s)`, var_name.min, var_name.max);

            with (func1) { stmt(E(var) = E(expr1)); }
            with (func2) { stmt(E(var) = E(expr2)); }
            return;
        }

        //Highly unsure if subtype should be handled at all
        auto var_minmax = xmlp.findMinMax(ns_name, var_name.type, DataItem());
        if (var_minmax.length > 0) {
            string expr1, expr2;
            if (var_minmax["defVal"].length == 0) {
                expr1 = format(`randomGenerator->generate(%s, "%s.%s.%s", %s, %s, %s)`, "vars",
                                                                                ciface_name.toLower,
                                                                                ditem_name, 
                                                                                var_name.name,
                                                                                var_minmax["min"],
                                                                                var_minmax["max"], "curr_cycles");
                expr2 = format(`randomGenerator->generate(%s, %s)`, var_minmax["min"], var_minmax["max"]);
            } else {
                expr1 = var_minmax["defVal"];
                expr2 = var_minmax["defVal"];
            }

            with (func1) { stmt(E(var) = E(expr1)); }
            with (func2) { stmt(E(var) = E(expr2)); }
        }
        else {
            string expr1 = format(`randomGenerator->generate(%s, "%s.%s.%s", %s)`, "vars", ciface_name.toLower,
                                                                                ditem_name, 
                                                                                var_name.name,
                                                                                "curr_cycles");
            string expr2 = `randomGenerator->generate()`;

            with (func1) { stmt(E(var) = E(expr1)); }
            with (func2) { stmt(E(var) = E(expr2)); }
        }
    }  
}

void generateCtor(const CppCtor a, CppModule inner) {
    import std.array : split;

    with (inner.ctor_body(a.name)) {
    }
}

void generateDtor(const CppDtor a, CppModule inner) {
    import std.array : split;

    with (inner.dtor_body(a.name[1 .. $])) {
    }
}

//TODO: Split this function to multiple and add cppm_type as a tag in translate()
@trusted void generateCppMeth(CppModule fuzz_, const CppMethod a, CppModule inner,
    string class_name, string nsname, Namespace ns) {

    import std.string;
    import std.array;
    import std.algorithm : map;
    import std.algorithm.searching : canFind;
    import cpptooling.analyzer.type;
    import cpptooling.data.representation;

    auto cppm_type = (cast(string)(a.name)).split("_")[0];
    auto cppm_ditem = (cast(string)(a.name)).split("_")[$ - 1];
    auto cppm_end_type = (cast(string)(a.name)).split("_")[$ - 1];

    switch(cppm_type) {
        case "Get":
            if(a.isPure) {
                generateGetFunc(a, inner, ns, class_name);
            } else {
                generateGetFunc(a, fuzz_, ns, class_name);
            }
            
            break;
        case "Put":
            generatePutFunc(a, inner, ns);
            break;
        case "Will":
            generateWillFunc(a, inner);
            break;
        default:
            switch(cppm_end_type) {
                case "Event": 
                    generateEventMeth(a, inner, ns);
                    break;
                case "Changed":
                    generateChangedFunc(a, inner, ns);
                    break;
                default:
                    switch(a.name) {
                        case "Connect_Port":
                            generateConnectPort(a, inner);
                            break;
                        case "Is_Client_Connected":
                            generateClientConnect(a, inner);
                            break;
                        default:
                            Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
                            with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, joinParams(a.paramRange))) {
                                return_;
                            }
                    }
                    break;
            }
            break;
    }
}

@trusted void generateChangedFunc(const CppMethod a, CppModule inner, Namespace ns) {
    import std.string : toLower;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        string func_name = a.name[0.. $-"_Changed".length];
        ContinousInterface ci = getInterface(ns, func_name);
        if(ci.name.length != 0) {
            func_name = func_name[ci.name.length .. $];
            if(func_name.length != 0 && func_name[0] == '_') 
                func_name = func_name[1..$];

            DataItem di = getDataItem(ns, ci, func_name);
            if (di.name.length == 0) {
                foreach(param ; a.paramRange) {
                    string paramName = paramNameToString(param);
                    stmt(E(ci.name.toLower ~ "." ~paramName) = E(paramName));
                }
            } else {
                stmt(E(ci.name.toLower ~ "." ~ di.name) = E(di.name));
            }
        }
    }

}

@trusted void generateGetFunc(const CppMethod a, CppModule inner, Namespace ns, string class_name) {
    import std.string : toLower, endsWith;
    import std.conv : to;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    if(a.name == "Get_Port") {
        with(inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, No.isConst)) {
            return_("*port");
        }
    } else if(a.name == "Get_Client_Id") {
        generateClientId(a, inner);
    } else if (a.name == "Get_Client_Name") {
        generateClientName(a, inner);
    } else if (a.name == "Get_Number_Of_Clients") {
        generateNumClients(a, inner);
    } else if ((to!string(a.name)).endsWith("_Bandwidth")) {
        generateBandwidth(a, inner);
    } else {
        Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
        string new_func_name; 
        
        if (a.isPure) {
            new_func_name = a.name;
        } else {
            new_func_name = class_name ~ "::" ~ a.name;
        }

        auto meth = inner.method_inline(No.isVirtual, a.returnType.toStringDecl, new_func_name, meth_const, joinParams(a.paramRange));
        with (meth) {
            string func_name = a.name["Get_".length .. $];
            ContinousInterface ci = getInterface(ns, func_name);
            if(ci.name.length != 0) {
                func_name = func_name[ci.name.length .. $];
                if(func_name.length != 0 && func_name[0] == '_') 
                    func_name = func_name[1..$];

                DataItem di = getDataItem(ns, ci, func_name);
                if (di.name.length == 0) {
                    MonitoredItem mi = getMonitoredItem(ns, ci, func_name);
                    if (mi.name.length == 0) {
                        return_(ci.name.toLower);
                    } else {
                        return_(ci.name.toLower ~ "." ~ mi.name);
                    }
                    
                } else {
                    return_(ci.name.toLower ~ "." ~ di.name);
                }
            }
        }
    }
}

@trusted void generateEventMeth(const CppMethod a, CppModule inner, Namespace ns) {
    import std.string : toLower;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange);
    string func_name = a.name[0 .. $-"_Event".length];
    Event event = getEvent(ns, func_name);
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
    if (event.name.length == 0) {
        with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
            return_;
        }
    } else {
        with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
            foreach(param ; a.paramRange) {
                string paramName = paramNameToString(param);
                stmt(E(event.name.toLower ~ "." ~ paramName) = E(paramName));
            }
        }
    }
}

@trusted void generatePutFunc(const CppMethod a, CppModule inner, Namespace ns) {
    import std.string : toLower;
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        string func_name = a.name["Put_".length .. $];
        ContinousInterface ci = getInterface(ns, func_name);
        if(ci.name.length != 0) {
            func_name = func_name[ci.name.length .. $];
            if(func_name.length != 0 && func_name[0] == '_') 
                func_name = func_name[1..$];

            DataItem di = getDataItem(ns, ci, func_name);
            if (di.name.length == 0) {
                foreach(param ; a.paramRange) {
                    string paramName = paramNameToString(param);
                    stmt(E(ci.name.toLower ~ "." ~paramName) = E(paramName));
                }
            } else {
                stmt(E(ci.name.toLower ~ "." ~ di.name) = E(di.name));
            }
        }
    }
}

@trusted void generateWillFunc(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        return_(E("randomGenerator->generate")("0, 1"));
    }
}

@trusted void generateConnectPort(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;
    /* if (Other_End.Is_Client_Connected(Get_Port_Impl().getName())) {
			Get_Port_Impl().Set_Other_End(&Other_End);
		}
    */
    auto params = joinParams(a.paramRange); 
    auto port_name = paramNameToString(a.paramRange[0]);
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        //with (if_(E(port_name ~ ".Is_Client_Connected")("Get_Port_Impl().getName()"))) {
            stmt(E("Get_Port_Impl()->Set_Other_End")("&" ~ port_name));
        //}
    }
}

@trusted void generateClientId(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;
    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        with(for_("int n = 0", "n < clients.size()", "n++")) {
            with(if_("clients[n] == client_name")) {
                return_("n");
            }
        }
        return_("-1");
    }
}

@trusted void generateClientName(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;

    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        with(if_("clients.size() != 0 && client_id < clients.size() && client_id > 0")) {
            return_("clients.at(client_id)");
        } 
        with(else_) {
            return_(`""`);
        }
    } 
}

@trusted void generateClientConnect(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;



    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        with(for_("int n = 0", "n < clients.size()", "n++")) {
            with(if_("clients[n] == client_name")) {
                    return_("true");
            }
        }
        return_("false");
    }
}

@trusted void generateNumClients(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;



    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        return_(E("clients.size")(""));
    }
}

@trusted void generateBandwidth(const CppMethod a, CppModule inner) {
    import cpptooling.data.representation;
    import cpptooling.analyzer.type;

    auto params = joinParams(a.paramRange); 
    Flag!"isConst" meth_const = a.isConst ? Yes.isConst : No.isConst;



    with (inner.method_inline(No.isVirtual, a.returnType.toStringDecl, a.name, meth_const, params)) {
        return_("1");
    }
}

@trusted Event getEvent(Namespace ns, string func_name) {
        import std.string : indexOf;

        foreach(ei ; ns.interfaces.ei) {
            foreach(event ; ei.events) {
                if(indexOf(func_name, event.name) == 0) {
                    return event;
                } 
            }
        }

    return Event("");
}

@trusted ContinousInterface getInterface(Namespace ns, string func_name) {
    ///func_name should have removed get_ or put_
    import std.string : indexOf;
    import std.algorithm : sort;

    foreach(ci ; ns.interfaces.ci.sort!("a.name.length > b.name.length")) {
        if(indexOf(func_name, ci.name) == 0) {
            return ci;
        } 
    }

    return ContinousInterface();   
}


@trusted DataItem getDataItem(Namespace ns, ContinousInterface ci, string func_name) {
    ///func_name should have removed Get_ or Put_ AND ci.name
    import std.string : indexOf;

    foreach(di; ci.data_items) {
        if (indexOf(func_name, di.name) == 0 && func_name[di.name.length .. $].length == 0) {
            return di;
        }
    }
    return DataItem();
}

@trusted MonitoredItem getMonitoredItem(Namespace ns, ContinousInterface ci, string func_name) {
    import std.string : indexOf;

    foreach(mi; ci.mon_items) {
        if (indexOf(func_name, mi.name) == 0 && func_name[mi.name.length .. $].length == 0) {
            return mi;
        }
    }
    return MonitoredItem();

}
