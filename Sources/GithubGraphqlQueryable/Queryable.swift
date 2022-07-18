import DeepCodable


/// Object that can generate a GraphQL query and be decoded from its response
public protocol GithubGraphqlQueryable: DeepDecodable {
	/**
	Shortcut type alias to allow `Node` to be used in the users' type declarations instead of the full type name

	This also has the advantage of scoping this short type name to within the conforming type, rather than polluting the global namespace.
	*/
	typealias Node = GithubGraphqlQueryTree<Self>

	/**
	Tree representing a GitHub GraphQL API query

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
	static var query: Node { get }
}

// Add some convenience type aliases for tree-building, to avoid polluting global namespace with short type names.
public extension GithubGraphqlQueryable {
	/**
	Shortcut type alias to allow `Field` to be used in the users' type declarations instead of the full type name

	This also has the advantage of scoping this short type name to within the conforming type, rather than polluting the global namespace.
	*/
	typealias Field         = GithubGraphqlField<Self>

	/**
	Shortcut type alias to allow `IfType` to be used in the users' type declarations instead of the full type name

	This also has the advantage of scoping this short type name to within the conforming type, rather than polluting the global namespace.
	*/
	typealias IfType        = GithubGraphqlIfType<Self>

	/**
	Shortcut type alias to allow `FieldList` to be used in the users' type declarations instead of the full type name

	This also has the advantage of scoping this short type name to within the conforming type, rather than polluting the global namespace.
	*/
	typealias FieldList     = GithubGraphqlFieldList<Self>

	/**
	Shortcut type alias to allow `FilteredField` to be used in the users' type declarations instead of the full type name

	This also has the advantage of scoping this short type name to within the conforming type, rather than polluting the global namespace.
	*/
	typealias FilteredField = GithubGraphqlFilteredField<Self>
}


// Add built-in conformance to `DeepDecodable` based on the query tree
public extension GithubGraphqlQueryable {
	/// Shortcut type alias to allow `CodingTree` to be used in internal definitions for simplicity
	typealias CodingTree = DeepCodingTree<Self>

	static var codingTree: CodingTree {
		return Self.query.codingTree
	}

	init(from decoder: Decoder) throws {
		var container: CodingTree.DecodingContainer = try decoder.container(keyedBy: DynamicStringCodingKey.self)

		// GraphQL's top-level response is wrapped with with `"data": { "node": { ... } }`, so if we're decoding at the top level, just consume those before invoking the rest of the decoding logic.
		if decoder.codingPath.isEmpty {
			container = try container.nestedContainer(keyedBy: DynamicStringCodingKey.self, forKey: .init(stringValue: "data"))
			container = try container.nestedContainer(keyedBy: DynamicStringCodingKey.self, forKey: .init(stringValue: "node"))
		}

		self.init()
		try Self.codingTree.decode(from: container, into: &self)
	}
}
