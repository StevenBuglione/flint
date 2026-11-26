/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

module flint.jakarta.persistence.named_entity_graph_test;

import flint.jakarta.persistence : NamedAttributeNode, NamedEntityGraph, NamedEntityGraphs, NamedSubgraph;
import flint.java.classref : classOf;

@safe:

@("named entity graph defaults leave the graph name and ordinary subgraph type to inference")
unittest
{
    enum graph = NamedEntityGraph();
    enum node = NamedAttributeNode("pets");
    enum subgraph = NamedSubgraph(name: "pet", attributeNodes: [NamedAttributeNode("name")]);
    static assert(graph.name == "" && !graph.includeAllAttributes);
    static assert(graph.attributeNodes.length == 0 && graph.subgraphs.length == 0);
    static assert(graph.subclassSubgraphs.length == 0);
    static assert(node.value == "pets" && node.subgraph == "" && node.keySubgraph == "");
    static assert(subgraph.type.name == "");
}

@("grouped graph metadata retains separate map key and value subgraphs and typed subclass nodes")
unittest
{
    static class PreferredOwner
    {
    }

    enum pets = NamedAttributeNode("pets", "petValue", "petKey");
    enum byType = NamedSubgraph(name: "petKey", attributeNodes: [NamedAttributeNode("description")]);
    enum byPet = NamedSubgraph(name: "petValue", attributeNodes: [NamedAttributeNode("name")]);
    enum discount = NamedAttributeNode("discount");
    enum preferred = NamedSubgraph("preferred", classOf!PreferredOwner, [discount]);
    enum owner = NamedEntityGraph("owner.pets", [pets], false, [byType, byPet], [preferred]);

    @NamedEntityGraphs([owner, NamedEntityGraph(name: "owner.all", includeAllAttributes: true)])
    static class Owner
    {
    }

    enum graphs = __traits(getAttributes, Owner)[0].value;
    static assert(graphs.length == 2 && graphs[1].includeAllAttributes);
    static assert(graphs[0].name == "owner.pets" && graphs[0].attributeNodes.length == 1);
    static assert(graphs[0].subgraphs[0].name == graphs[0].attributeNodes[0].keySubgraph);
    static assert(graphs[0].subgraphs[1].name == graphs[0].attributeNodes[0].subgraph);
    static assert(graphs[0].subgraphs[1].attributeNodes[0].value == "name");
    static assert(graphs[0].subclassSubgraphs[0].type == classOf!PreferredOwner);
    static assert(graphs[0].subclassSubgraphs[0].attributeNodes[0].value == "discount");
}
