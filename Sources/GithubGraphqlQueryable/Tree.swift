import DeepCodable


/**
Object containing the tree structure representing the GitHub GraphQL API query and its results (which mirror the structure to a large degree)

Designed to be instantiated using result builder syntax; for example:
```swift
static let query = Node(type: "SomeGraphqlType") {
	Field("someRootFieldName") {
		IfType("OtherGraphqlType") {
			Field("otherFieldName", containing: \._someProperty)
		}
	}

	Field("otherRootFieldName", containing: \._otherProperty)
}
```
*/
public struct GithubGraphqlQueryTree<Root: DeepDecodable> {
	/// Helper object to enable result builder syntax for defining a query tree
	@resultBuilder
	public struct TreeBuilder<Root: DeepDecodable> {
		/// Shortcut alias for the type of a node in the tree
		public typealias Node = AnyGithubGraphqlQueryNode<Root>

		/**
		Build a type-erased node from a concrete implementation, which can't be used directly in an array.

		- Parameter node: concrete node to be type-erased
		- Returns: A type-erased copy of the input node, copying over all query-generation and decoding values
		*/
		public static func buildExpression<Erasee: GithubGraphqlQueryNode>(_ node: Erasee) -> Node where Erasee.Root == Root {
			return Node(erasing: node)
		}

		/**
		Aggregate result builder-defined nodes into a list for initializing a parent node (or tree root).

		- Parameter nodes: nodes representing the keys at a given level of hierarchy on the query tree
		- Returns: A list of nodes to be stored as children on the parent node
		*/
		public static func buildBlock(_ nodes: Node...) -> [Node] {
			return nodes
		}
	}


	/// Shortcut alias for the type of the result builder helper struct
	public typealias Builder = TreeBuilder<Root>
	/// Shortcut alias for the type of the node in the query tree
	public typealias Node    = Builder.Node


	/// Type of the root GraphQL node being queried, since all GitHub GraphQL queries start with a specific node ID
	internal let type: String
	/// Top-level nodes in the tree
	internal let nodes: [Node]

	/// Partial query represented by this tree, excluding the boilerplate `"data": { "node": { ... } }` wrapper so the query can be spliced into another one
	internal let partialQuery: String

	/// Coding tree corresponding to this query tree, to decode the response using `DeepDecodable`
	internal let codingTree: DeepCodingTree<Root>

	/**
	Initialize an instance from the output of a result builder defining the top-level nodes of the tree.

	- Parameters:
		- type: type of the root GraphQL node being queried
		- builder: closure representing the output of a result builder block containing this node's children
	*/
	public init(type: String, @Builder _ builder: () -> [Node]) {
		self.type  = type

		let nodes = builder()
		self.nodes = nodes

		var childQueries =
			nodes
			.map { $0.partialQuery }
			.joined(separator: " ")
		if childQueries != "" {
			childQueries = " \(childQueries) "
		}
		self.partialQuery = "... on \(self.type) {\(childQueries)}"

		let childNodes = nodes.flatMap { $0.codingNodes }
		self.codingTree = .init(nodes: childNodes)
	}


	/**
	Build a complete top-level query from this tree from a given node ID.

	This allows generating the query using `Type.query(id: ...)` rather than something like `Type.query.query(id: ...)`

	- Parameter id: unique ID of the root node being queried
	- Returns: A complete query string representing this tree to be sent to a GraphQL server
	*/
	public func callAsFunction(id: String) -> String {
		var partialQuery = self.partialQuery
		if partialQuery != "" {
			partialQuery = " \(partialQuery) "
		}
		return """
			query { node(id: "\(id)") {\(partialQuery)} }
			"""
	}
}
