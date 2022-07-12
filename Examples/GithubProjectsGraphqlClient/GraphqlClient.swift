import Foundation

import ArgumentParser
import AsyncHTTPClient
import Yams

import GithubGraphqlClient
import GithubGraphqlQueryable


/// An object representing configuration values for the GraphQL client
struct GraphqlClientConfiguration: Codable {
	/// GitHub App ID used to perform the API call
	let appId: String
	/// GitHub App private key (PEM-encoded) used to perform the API call
	let privateKey: String

	/// Name of user/organization the GitHub App is installed on, to fetch an installation access token
	let username: String
}

struct ProjectItem: GithubGraphqlQueryable, CustomStringConvertible {
	struct Project: GithubGraphqlQueryable {
		static let query = Node(type: "ProjectV2") {
			Field("title", containing: \._title)
			Field("url", containing: \._url)
		}

		@Value var title: String
		@Value var url: String
	}

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

	var status: String? {
		let statusField = fieldValues.first { $0.field == "Status" }
		return statusField?.value
	}

	var description: String {
		return """
			title: \(self.title)
			url: \(self.url ?? "(None)")
			project:
				title: \(self.project.title)
				url: \(self.project.url)
			status: \(self.status ?? "(None)")
			"""
	}
}

struct GraphqlRequest: Encodable {
	let query: String
}


@main
struct GraphqlClient: AsyncParsableCommand {
	@Option(name: [.customLong("config"), .short], help: "Path to config file to pull credentials and configuration information from")
	var configurationFile: String = "config.yaml"

	@Argument(help: "Projects V2 Item node ID for querying the GraphQL API (starts with `PVTI_`)")
	var itemId: String


	func run() async throws {
		let configurationData: Data = try .init(contentsOf: .init(fileURLWithPath: configurationFile))
		let decoder = YAMLDecoder()
		let configuration = try decoder.decode(GraphqlClientConfiguration.self, from: configurationData)

		let client: GithubGraphqlClient = try await .init(
			appId: configuration.appId,
			privateKey: configuration.privateKey,
			installationLogin: configuration.username
		)

		do {
			let item = try await client.query(ProjectItem.self, id: self.itemId)
			print(item)
		}
		catch GithubGraphqlClientError.httpError(let response) {
			print("Status: \(response.status)")

			let responseBody: Data = .init(buffer: try await response.body.collect(upTo: 10 * 1024))
			print("Body:")
			print(String(data: responseBody, encoding: .utf8)!)

			throw ExitCode.failure
		}
	}
}
