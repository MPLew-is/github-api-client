import XCTest

import GithubGraphqlQueryable


/// Test some examples from real-world usage, for both query-generation and decoding.
final class RealWorldTests: XCTestCase {
	/// Example object representing selected fields and child objects of a GitHub Projects (V2) item
	struct ProjectItem: GithubGraphqlQueryable {
		/// Example object representing selected fields and child objects of a GitHub Projects (V2) project
		struct Project: GithubGraphqlQueryable {
			static let query = Node(type: "ProjectV2") {
				Field("title", containing: \._title)
				Field("url", containing: \._url)
			}

			@Value var title: String
			@Value var url: String
		}

		/// Example object representing selected fields and child objects of a GitHub Projects (V2) field
		struct ProjectFieldValue: GithubGraphqlQueryable {
			static let query = Node(type: "ProjectV2ItemFieldSingleSelectValue") {
				Field("name", containing: \._value)
				Field("field") {
					IfType("ProjectV2FieldCommon") {
						Field("name", containing: \._field)
					}
				}
			}

			@Value var field: String?
			@Value var value: String?
		}


		static let query = Node(type: "ProjectV2Item") {
			Field("content") {
				IfType("DraftIssue") {
					Field("title", containing: \._title)
				}

				IfType("Issue") {
					Field("title", containing: \._title)
					Field("url", containing: \._url)
				}

				IfType("PullRequest") {
					Field("title", containing: \._title)
					Field("url", containing: \._url)
				}
			}

			FieldList("fieldValues", first: 10, containing: \._fieldValues)

			Field("project", containing: \._project)
		}

		@Value var title: String
		@Value var url: String?
		@Value var project: Project
		@Value var fieldValues: [ProjectFieldValue]
	}

	/// Test that creating a query for a specific project item generates the expected value (including queries for its nested types).
	func testProjectItemQuery() throws {
		let id: String = "PVTI_ABCD1234"
		let expected = """
			query { node(id: "\(id)") { ... on ProjectV2Item { content { ... on DraftIssue { title } ... on Issue { title url } ... on PullRequest { title url } } fieldValues(first: 10) { nodes { ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } } } } project { ... on ProjectV2 { title url } } } } }
			"""
		let actual = ProjectItem.query(id: id)

		XCTAssertEqual(expected, actual)
	}

	/// Test that decoding a project item from sample JSON produces the expected values.
	func testProjectItemDecoding() throws {
		let json = """
			{
				"data": {
					"node": {
						"content": {
							"title": "Example title"
						},
						"fieldValues": {
							"nodes": [
								{},
								{},
								{
									"name": "Example field value",
									"field": {
										"name": "Example field name"
									}
								}
							]
						},
						"project": {
							"title": "Example project title",
							"url": "Example project URL"
						}
					}
				}
			}
			"""
		let decoded = try JSONDecoder().decode(ProjectItem.self, from: json.data(using: .utf8)!)


		XCTAssertEqual("Example title", decoded.title)

		let fieldValues = decoded.fieldValues
		XCTAssertEqual(3, fieldValues.count)

		let fieldValue1 = fieldValues[0]
		XCTAssertNil(fieldValue1.field)
		XCTAssertNil(fieldValue1.value)

		let fieldValue2 = fieldValues[1]
		XCTAssertNil(fieldValue2.field)
		XCTAssertNil(fieldValue2.value)

		let fieldValue3 = fieldValues[2]
		XCTAssertEqual("Example field name", fieldValue3.field)
		XCTAssertEqual("Example field value", fieldValue3.value)

		let project = decoded.project
		XCTAssertEqual("Example project title", project.title)
		XCTAssertEqual("Example project URL", project.url)
	}


	/// Test that creating a query for a specific project generates the expected value.
	func testProjectQuery() throws {
		let id: String = "PVT_ABCD1234"
		let expected = """
			query { node(id: "\(id)") { ... on ProjectV2 { title url } } }
			"""
		let actual = ProjectItem.Project.query(id: id)

		XCTAssertEqual(expected, actual)
	}

	/// Test that decoding a project from sample JSON produces the expected values.
	func testProjectDecoding() throws {
		let json = """
			{
				"data": {
					"node": {
						"title": "Example project title",
						"url": "Example project URL"
					}
				}
			}
			"""
		let decoded = try JSONDecoder().decode(ProjectItem.Project.self, from: json.data(using: .utf8)!)

		XCTAssertEqual("Example project title", decoded.title)
		XCTAssertEqual("Example project URL", decoded.url)
	}


	/// Test that creating a query for a specific project field value generates the expected value.
	func testProjectFieldValueQuery() throws {
		let id: String = "PVTFSV_ABCD1234"
		let expected = """
			query { node(id: "\(id)") { ... on ProjectV2ItemFieldSingleSelectValue { name field { ... on ProjectV2FieldCommon { name } } } } }
			"""
		let actual = ProjectItem.ProjectFieldValue.query(id: id)

		XCTAssertEqual(expected, actual)
	}

	/// Test that decoding a project field value from sample JSON produces the expected values.
	func testProjectFieldValueDecoding() throws {
		let json = """
			{
				"data": {
					"node": {
						"name": "Example field value",
						"field": {
							"name": "Example field name"
						}
					}
				}
			}
			"""
		let decoded = try JSONDecoder().decode(ProjectItem.ProjectFieldValue.self, from: json.data(using: .utf8)!)

		XCTAssertEqual("Example field value", decoded.value)
		XCTAssertEqual("Example field name", decoded.field)
	}


	/// Example object representing selected fields and child objects of a GitHub Projects (V2) single-select field
	struct ProjectField: GithubGraphqlQueryable {
		/// Example object representing a GitHub Projects (V2) single-select field option
		struct Option: GithubGraphqlQueryable {
			static let query = Node(type: "ProjectV2SingleSelectFieldOption") {
				Field("id", containing: \._id)
				Field("name", containing: \._name)
			}

			@Value var id: String
			@Value var name: String
		}

		static let query = Node(type: "ProjectV2SingleSelectField") {
			Field("options", containing: \._options)
		}

		@Value var options: [Option]
	}

	/// Test that creating a query for an array of field options generates the expected value.
	func testProjectFieldOptionsQuery() throws {
		let id = "PVTSSF_ABCD1234"
		let expected = """
			query { node(id: "\(id)") { ... on ProjectV2SingleSelectField { options { ... on ProjectV2SingleSelectFieldOption { id name } } } } }
			"""
		let actual = ProjectField.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that decoding a project field options list from sample JSON produces the expected values.
	func testProjectFieldOptionsDecoding() throws {
		let json = """
			{
				"data": {
					"node": {
						"options": [
							{
								"id": "aaaa",
								"name": "Example 1"
							},
							{
								"id": "bbbb",
								"name": "Example 2"
							},
							{
								"id": "cccc",
								"name": "Example 3"
							},
							{
								"id": "dddd",
								"name": "Example 4"
							},
							{
								"id": "eeee",
								"name": "Example 5"
							}
						]
					}
				}
			}
			"""
		let decoded = try JSONDecoder().decode(ProjectField.self, from: json.data(using: .utf8)!)

		let options = decoded.options

		XCTAssertEqual(5, options.count)

		XCTAssertEqual("aaaa", options[0].id)
		XCTAssertEqual("Example 1", options[0].name)

		XCTAssertEqual("bbbb", options[1].id)
		XCTAssertEqual("Example 2", options[1].name)

		XCTAssertEqual("cccc", options[2].id)
		XCTAssertEqual("Example 3", options[2].name)

		XCTAssertEqual("dddd", options[3].id)
		XCTAssertEqual("Example 4", options[3].name)

		XCTAssertEqual("eeee", options[4].id)
		XCTAssertEqual("Example 5", options[4].name)
	}


	/// Example object representing selected fields and child objects of a GitHub Projects (V2) project
	struct Project: GithubGraphqlQueryable {
		/// Example object representing selected fields of a GitHub Projects (V2) single-select field (without child objects)
		struct ProjectFieldShallow: GithubGraphqlQueryable {
			static let query = Node(type: "ProjectV2SingleSelectField") {
				Field("name", containing: \._name)
			}

			@Value var name: String
		}

		static let query = Node(type: "ProjectV2") {
			FilteredField("field", name: "Status", containing: \._field)
		}

		@Value var field: ProjectFieldShallow?
	}

	/// Test that creating a query for a field with arguments generates the expected value.
	func testProjectFilteredFieldQuery() throws {
		let id = "PVT_ABCD1234"
		let expected = """
			query { node(id: "\(id)") { ... on ProjectV2 { field(name: "Status") { ... on ProjectV2SingleSelectField { name } } } } }
			"""
		let actual = Project.query(id: id)
		XCTAssertEqual(expected, actual)
	}

	/// Test that decoding a project field options list from sample JSON produces the expected values.
	func testProjectFilteredFieldDecoding() throws {
		let json = """
			{
				"data": {
					"node": {
						"field": {
							"name": "Example"
						}
					}
				}
			}
			"""
		let decoded = try JSONDecoder().decode(Project.self, from: json.data(using: .utf8)!)

		XCTAssertNotNil(decoded.field)
		XCTAssertEqual("Example", decoded.field?.name)
	}
}
