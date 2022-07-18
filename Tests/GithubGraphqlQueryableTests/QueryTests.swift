import XCTest

import GithubGraphqlQueryable


/// Test query generation with different types and layouts.
final class QueryTests: XCTestCase {
	/// Test that a type with a single field generates the correct query.
	func testSingleField() throws {
		struct SingleField: GithubGraphqlQueryable {
			static let query = Node(type: "SingleField") {
				Field("example", containing: \._example)
			}

			@Value var example: String
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on SingleField { example } } }
			"""
		let actual = SingleField.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	// Test that a type with multiple fields generates the correct query.
	func testMultipleFields() throws {
		struct MultipleFields: GithubGraphqlQueryable {
			static let query = Node(type: "MultipleFields") {
				Field("example1", containing: \._example1)
				Field("example2", containing: \._example2)
			}

			@Value var example1: String
			@Value var example2: String
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on MultipleFields { example1 example2 } } }
			"""
		let actual = MultipleFields.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	// Test that a type with multiple fields at different levels generates the correct query.
	func testFieldsAtDifferentLevels() throws {
		struct FieldsAtDifferentLevels: GithubGraphqlQueryable {
			static let query = Node(type: "FieldsAtDifferentLevels") {
				Field("example1", containing: \._example1)

				Field("container") {
					Field("example2", containing: \._example2)
				}
			}

			@Value var example1: String
			@Value var example2: String
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on FieldsAtDifferentLevels { example1 container { example2 } } } }
			"""
		let actual = FieldsAtDifferentLevels.query(id: id)
		XCTAssertEqual(expected, actual)
	}


	/// Test that a type with a single inline fragment generates the correct query.
	func testSingleIfType() throws {
		struct SingleIfType: GithubGraphqlQueryable {
			static let query = Node(type: "SingleIfType") {
				IfType("Example") {}
			}
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on SingleIfType { ... on Example {} } } }
			"""
		let actual = SingleIfType.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that a type with multiple inline fragments generates the correct query.
	func testMultipleIfType() throws {
		struct MultipleIfType: GithubGraphqlQueryable {
			static let query = Node(type: "MultipleIfType") {
				IfType("Example1") {}

				IfType("Example2") {}
			}
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on MultipleIfType { ... on Example1 {} ... on Example2 {} } } }
			"""
		let actual = MultipleIfType.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that a type with multiple inline fragments at different levels generates the correct query.
	func testIfTypesAtDifferentLevels() throws {
		struct IfTypesAtDifferentLevel: GithubGraphqlQueryable {
			static let query = Node(type: "IfTypesAtDifferentLevel") {
				IfType("Example1") {}

				Field("container") {
					IfType("Example2") {}
				}
			}
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on IfTypesAtDifferentLevel { ... on Example1 {} container { ... on Example2 {} } } } }
			"""
		let actual = IfTypesAtDifferentLevel.query(id: id)
		XCTAssertEqual(expected, actual)
	}


	/// Test that a type with a single field list generates the correct query.
	func testSingleFieldList() throws {
		struct SingleFieldList: GithubGraphqlQueryable {
			struct NestedField: GithubGraphqlQueryable {
				static let query = Node(type: "NestedField") {}
			}

			static let query = Node(type: "SingleFieldList") {
				FieldList("example", first: 1, containing: \._list)
			}

			@Value var list: [NestedField]
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on SingleFieldList { example(first: 1) { nodes { ... on NestedField {} } } } } }
			"""
		let actual = SingleFieldList.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that a type with multiple field lists generates the correct query.
	func testMultipleFieldLists() throws {
		struct MultipleFieldLists: GithubGraphqlQueryable {
			struct NestedField: GithubGraphqlQueryable {
				static let query = Node(type: "NestedField") {}
			}

			static let query = Node(type: "MultipleFieldLists") {
				FieldList("example1", first: 1, containing: \._list1)

				FieldList("example2", first: 2, containing: \._list1)
			}

			@Value var list1: [NestedField]
			@Value var list2: [NestedField]
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on MultipleFieldLists { example1(first: 1) { nodes { ... on NestedField {} } } example2(first: 2) { nodes { ... on NestedField {} } } } } }
			"""
		let actual = MultipleFieldLists.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that a type with multiple field lists at different levels generates the correct query.
	func testFieldListsAtDifferentLevels() throws {
		struct FieldListsAtDifferentLevels: GithubGraphqlQueryable {
			struct NestedField: GithubGraphqlQueryable {
				static let query = Node(type: "NestedField") {}
			}

			static let query = Node(type: "FieldListsAtDifferentLevels") {
				FieldList("example1", first: 1, containing: \._list1)

				Field("container") {
					FieldList("example2", first: 2, containing: \._list1)
				}
			}

			@Value var list1: [NestedField]
			@Value var list2: [NestedField]
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on FieldListsAtDifferentLevels { example1(first: 1) { nodes { ... on NestedField {} } } container { example2(first: 2) { nodes { ... on NestedField {} } } } } } }
			"""
		let actual = FieldListsAtDifferentLevels.query(id: id)
		XCTAssertEqual(expected, actual)
	}


	/// Test that a type with using all types of query nodes generates the correct query.
	func testAllTypes() throws {
		struct AllTypes: GithubGraphqlQueryable {
			struct NestedField: GithubGraphqlQueryable {
				static let query = Node(type: "NestedField") {}
			}

			static let query = Node(type: "AllTypes") {
				Field("field", containing: \._field)

				IfType("Type") {}

				FieldList("list", first: 1, containing: \._list)
			}

			@Value var field: String
			@Value var list: [NestedField]
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on AllTypes { field ... on Type {} list(first: 1) { nodes { ... on NestedField {} } } } } }
			"""
		let actual = AllTypes.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that a type containing another nested queryable type generates the correct query.
	func testNestedType() throws {
		struct ContainingType: GithubGraphqlQueryable {
			struct NestedType: GithubGraphqlQueryable {
				static let query = Node(type: "NestedType") {
					Field("example", containing: \._example)
				}

				@Value var example: String
			}


			static let query = Node(type: "ContainingType") {
				Field("nested", containing: \._nested)
			}

			@Value var nested: NestedType
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on ContainingType { nested { ... on NestedType { example } } } } }
			"""
		let actual = ContainingType.query(id: id)
		XCTAssertEqual(expected, actual)
	}


	/// Test that an array of decodable fields still produces the correct query.
	func testFieldArrayDecodable() throws {
		struct FieldArrayDecodable: GithubGraphqlQueryable {
			static let query = Node(type: "FieldArrayDecodable") {
				Field("example", containing: \._example)
			}

			@Value var example: [String]
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on FieldArrayDecodable { example } } }
			"""
		let actual = FieldArrayDecodable.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that an array of other queryable fields produces the correct query (should be identical to if it were just a normal single-value field).
	func testFieldArrayQueryable() throws {
		struct FieldArrayQueryable: GithubGraphqlQueryable {
			struct NestedType: GithubGraphqlQueryable {
				static let query = Node(type: "NestedType") {
					Field("example", containing: \._example)
				}

				@Value var example: String
			}

			static let query = Node(type: "FieldArrayQueryable") {
				Field("nested", containing: \._nested)
			}

			@Value var nested: [NestedType]
		}

		let id = "Test"
		let expected = """
			query { node(id: "\(id)") { ... on FieldArrayQueryable { nested { ... on NestedType { example } } } } }
			"""
		let actual = FieldArrayQueryable.query(id: id)
		XCTAssertEqual(expected, actual)
	}
}
