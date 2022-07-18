import DeepCodable


/// Type representing a node on the GitHub GraphQL query tree
public protocol GithubGraphqlQueryNode {
	/// Type of the root object being represented by this query
	associatedtype Root: DeepDecodable

	/// Partial query fragment representing this node and all of its children
	var partialQuery: String { get }

	/// Shortcut type alias to allow `CodingNode` to be used in internal definitions for simplicity
	typealias CodingNode = DeepCodingNode<Root>
	/// Nodes representing the decoding tree to decode the root type from a GraphQL response
	var codingNodes: [CodingNode] { get }
}

/*
Add some convenience type aliases for tree-building for internal types.

These are public due to being used in public-facing declarations.
*/
public extension GithubGraphqlQueryNode {
	/// Shortcut type alias to allow `Tree` to be used in internal definitions for simplicity
	typealias Tree        = GithubGraphqlQueryTree<Root>
	/// Shortcut type alias to allow `Builder` to be used in internal definitions for simplicity
	typealias Builder     = Tree.Builder
	/// Shortcut type alias to allow `Node` to be used in internal definitions for simplicity
	typealias Node        = Tree.Node

	/// Shortcut type alias to allow `CodingValue` to be used in internal definitions for simplicity
	typealias CodingValue = DeepCodingValue
}


/**
Type-erasing wrapper for the other node types, preserving all query-generating and and decoding behaviors from the erased node

This is necessary since we can't have an array of existentials (bare protocol types), so copy over just what we need into a concrete wrapper and use that instead.
*/
public struct AnyGithubGraphqlQueryNode<Root: DeepDecodable>: GithubGraphqlQueryNode {
	// This alias seems to be required for the compiler to reason about the types, see [a related post on the Swift forums](https://forums.swift.org/t/what-are-the-rules-on-inheriting-associated-types-from-protocols/58757/7).
	public typealias Root = Root

	public let partialQuery: String
	public let codingNodes: [CodingNode]

	/**
	Initialize an instance by copying values from a target instance.

	- Parameter node: other node to type-erase
	*/
	public init<Erasee: GithubGraphqlQueryNode>(erasing node: Erasee) where Erasee.Root == Root {
		self.partialQuery = node.partialQuery
		self.codingNodes  = node.codingNodes
	}
}


/// Object representing [a normal GraphQL field](https://graphql.org/learn/queries/#fields)
public struct GithubGraphqlField<Root: DeepDecodable>: GithubGraphqlQueryNode {
	// This alias seems to be required for the compiler to reason about the types, see [a related post on the Swift forums](https://forums.swift.org/t/what-are-the-rules-on-inheriting-associated-types-from-protocols/58757/7).
	public typealias Root = Root

	/// Name of this field, in both queries and responses
	internal let name: String
	/// Immediate children of this node
	internal let children: [Node]?

	public let partialQuery: String
	public let codingNodes: [CodingNode]

	/**
	Initialize an instance containing child nodes from a result builder.

	- Parameters:
		- name: name of the field this node represents
		- builder: closure representing the output of a result builder block containing this node's children
	*/
	public init(_ name: String, @Builder _ builder: () -> [Node]) {
		self.name = name

		let children = builder()
		self.children = children

		var childQueries =
			children.map { $0.partialQuery }
			.joined(separator: " ")
		if childQueries != "" {
			childQueries = " \(childQueries) "
		}
		self.partialQuery = "\(self.name) {\(childQueries)}"

		let childCodingNodes = children.flatMap { $0.codingNodes }
		self.codingNodes = [.init(name, children: childCodingNodes)]
	}


	/**
	Initialize an instance capturing a non-optional value to decode.

	This method type-erases the input key path's value type via passing it down to the corresponding `DeepCodingNode` initializer.

	- Parameters:
		- name: name of the field this node represents
		- targetPath: key path into the root type where the decoded response value should be written
	*/
	public init<Value: Decodable>(_ name: String, containing targetPath: KeyPath<Root, CodingValue<Value>>) {
		self.name = name

		self.children = nil

		self.partialQuery = name

		self.codingNodes = [.init(name, containing: targetPath)]
	}

	/**
	Initialize an instance capturing an optional value to decode.

	This method type-erases the input key path's value type via passing it down to the corresponding `DeepCodingNode` initializer.

	- Parameters:
		- name: name of the field this node represents
		- targetPath: key path into the root type where the decoded response value should be written
	*/
	public init<Value: Decodable>(_ name: String, containing targetPath: KeyPath<Root, CodingValue<Value?>>) {
		self.name = name

		self.children = nil

		self.partialQuery = name

		self.codingNodes = [.init(name, containing: targetPath)]
	}

	/**
	Initialize an instance capturing another `GithubGraphqlQueryable` object.

	We need this extra specialization here to be able to bridge between query trees with different root types, which would otherwise violate the generic constraints.
	This method type-erases the input key path's value type via passing it down to the corresponding `DeepCodingNode` initializer.

	- Parameters:
		- name: name of the field this node represents
		- targetPath: key path into the root type holding another object representing a GraphQL query
	*/
	public init<Value: GithubGraphqlQueryable>(_ name: String, containing targetPath: KeyPath<Root, CodingValue<Value>>) {
		self.name = name

		self.children = nil

		// Since the coding nodes already traverse nested type boundaries just fine, we just need to bridge the queries together, which is easy since we can just insert the partial query from the other type.
		var childQuery = Value.query.partialQuery
		if childQuery != "" {
			childQuery = " \(childQuery) "
		}
		self.partialQuery = "\(name) {\(childQuery)}"

		// `DeepDecodable` (really mostly just `Decodable`) already handles traversing type boundaries, no need for anything special here.
		self.codingNodes = [.init(name, containing: targetPath)]
	}

	/**
	Initialize an instance capturing an array of other `GithubGraphqlQueryable` objects.

	This is distinct from a `FieldList` in that [the query shares the same syntax as just accessing a singular property](https://graphql.org/learn/queries/#fields), it just needs to be decoded into an array.

	We need this extra specialization here to be able to bridge between query trees with different root types, which would otherwise violate the generic constraints.
	This method type-erases the input key path's value type via passing it down to the corresponding `DeepCodingNode` initializer.

	- Parameters:
		- name: name of the field this node represents
		- targetPath: key path into the root type holding another object representing a GraphQL query
	*/
	public init<Value: GithubGraphqlQueryable>(_ name: String, containing targetPath: KeyPath<Root, CodingValue<Array<Value>>>) {
		self.name = name

		self.children = nil

		// Since the coding nodes already traverse nested type boundaries just fine, we just need to bridge the queries together, which is easy since we can just insert the partial query from the other type.
		var childQuery = Value.query.partialQuery
		if childQuery != "" {
			childQuery = " \(childQuery) "
		}
		self.partialQuery = "\(name) {\(childQuery)}"

		// `DeepDecodable` (really mostly just `Decodable`) already handles traversing type boundaries, no need for anything special here.
		self.codingNodes = [.init(name, containing: targetPath)]
	}
}


/// Object representing [a GraphQL inline fragment](https://graphql.org/learn/queries/#inline-fragments)
public struct GithubGraphqlIfType<Root: DeepDecodable>: GithubGraphqlQueryNode {
	// This alias seems to be required for the compiler to reason about the types, see [a related post on the Swift forums](https://forums.swift.org/t/what-are-the-rules-on-inheriting-associated-types-from-protocols/58757/7).
	public typealias Root = Root


	/// GraphQL type the containing field is being cast to
	internal let type: String
	/// Immediate children of this node
	internal let children: [Node]

	public let partialQuery: String
	public let codingNodes: [CodingNode]

	/**
	Initialize an instance containing child nodes from a result builder.

	- Parameters:
		- name: GraphQL type the containing field should be cast to
		- builder: closure representing the output of a result builder block containing this node's children
	*/
	public init(_ type: String, @Builder _ builder: () -> [Node]) {
		self.type = type

		let children = builder()
		self.children = children

		var childQueries =
			children.map { $0.partialQuery }
			.joined(separator: " ")
		if childQueries != "" {
			childQueries = " \(childQueries) "
		}
		self.partialQuery = "... on \(type) {\(childQueries)}"

		self.codingNodes = children.flatMap { $0.codingNodes }
	}
}


/// Object representing [a GraphQL list type](https://graphql.org/learn/schema/#lists-and-non-null), which must contain another `GithubGraphqlQueryable` object
public struct GithubGraphqlFieldList<Root: DeepDecodable>: GithubGraphqlQueryNode {
	// This alias seems to be required for the compiler to reason about the types, see [a related post on the Swift forums](https://forums.swift.org/t/what-are-the-rules-on-inheriting-associated-types-from-protocols/58757/7).
	public typealias Root = Root


	/// Name of the field containing the list of other nodes
	internal let name: String

	public let partialQuery: String
	public let codingNodes: [CodingNode]


	/**
	Initialize an instance capturing another `GithubGraphqlQueryable` object.

	Since we're capturing a list of other types, we mandate that the targeted field be another `GithubGraphqlQueryable` object, otherwise the decoding is a nightmare.

	This method type-erases the input key path's value type via passing it down to the corresponding `DeepCodingNode` initializer.

	- Parameters:
		- name: name of the field this node represents
		- firstCount: number of nodes to query in the output list, from the beginning
		- targetPath: key path into the root type holding another object representing a GraphQL query
	*/
	public init<Value: GithubGraphqlQueryable>(_ name: String, first firstCount: UInt, containing targetPath: KeyPath<Root, CodingValue<Array<Value>>>) {
		self.name = name

		var childQuery = Value.query.partialQuery
		if childQuery != "" {
			childQuery = " \(childQuery) "
		}
		self.partialQuery = "\(name)(first: \(firstCount)) { nodes {\(childQuery)} }"

		// When querying a list, GitHub's API inserts an extra key into the result, so just consume that here.
		let nodesNode: CodingNode = .init("nodes", containing: targetPath)
		self.codingNodes = [.init(name, children: [nodesNode])]
	}
}


/// Object representing [a GraphQL field with arguments](https://graphql.org/learn/schema/#arguments), which must contain another `GithubGraphqlQueryable` object
public struct GithubGraphqlFilteredField<Root: DeepDecodable>: GithubGraphqlQueryNode {
	// This alias seems to be required for the compiler to reason about the types, see [a related post on the Swift forums](https://forums.swift.org/t/what-are-the-rules-on-inheriting-associated-types-from-protocols/58757/7).
	public typealias Root = Root


	/// Name of the field containing the list of other nodes
	internal let name: String

	public let partialQuery: String
	public let codingNodes: [CodingNode]


	/**
	Initialize an instance capturing another `GithubGraphqlQueryable` object.

	Since we're filtering a field based on an argument, we require the child type to be optional since the filter may not produce any results.
	We also require this to be another `GithubGraphqlQueryable` object since we have to have sub-fields selected to actually construct a query.

	This method type-erases the input key path's value type via passing it down to the corresponding `DeepCodingNode` initializer.

	- Parameters:
		- name: name of the field this node represents
		- filterName: argument value to the "name" argument being filtered on
		- targetPath: key path into the root type holding another object representing a GraphQL query
	*/
	public init<Value: GithubGraphqlQueryable>(_ name: String, name filterName: String, containing targetPath: KeyPath<Root, CodingValue<Value?>>) {
		self.name = name

		var childQuery = Value.query.partialQuery
		if childQuery != "" {
			childQuery = " \(childQuery) "
		}
		self.partialQuery = "\(name)(name: \"\(filterName)\") {\(childQuery)}"

		self.codingNodes = [.init(name, containing: targetPath)]
	}
}
