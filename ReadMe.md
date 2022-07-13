# GitHub GraphQL Client #

This package provides a GitHub GraphQL API client, automatically handling:
- [Authenticating as a GitHub App](https://docs.github.com/en/developers/apps/building-github-apps/authenticating-with-github-apps#authenticating-as-a-github-app)
- Building GraphQL queries from Swift objects
- Decoding Swift objects from GraphQL responses

The GraphQL interface is handled by defining your query using a simple Result Builder interface:
```swift
static let query = Node(type: "ProjectV2") {
	Field("title")
	Field("url")
}
```

Using this tree, the actual GraphQL query string can be automatically generated, as can the translation from the JSON result into an instance of your type.

GraphQL functionality is currently designed only for GitHub's GraphQL API and may not function correctly with any other GraphQL server.
Additionally, this is still in **extremely early development** and may not yet support even all GitHub GraphQL querying operations.


## Quick Start ##

Pre-built examples:
- [GitHub Actions Webhook example](./Examples/GithubActionsWebhookClient): command-line utility that invokes an Actions webhook on a configured repository as a GitHub App (does not use any GraphQL functionality, only the GitHub API client)
- [GitHub Projects GraphQL example](./Examples/GithubProjectsGraphqlClient): command-line utility that fetches information about a GitHub Projects (V2) item given an input node ID, authenticating as a GitHub App


Add to your `Package.Swift`:
```swift
...
	dependencies: [
		...
		.package(url: "https://github.com/MPLew-is/github-graphql-client", branch: "main"),
	],
	targets: [
		...
		.target(
			...
			dependencies: [
				...
				.product(name: "GithubGraphqlClient", package: "github-graphql-client"),
				.product(name: "GithubGraphqlQueryable", package: "github-graphql-client"),
			]
		),
		...
	]
]
```

Query a test object from the GitHub GraphQL API:
```swift
import GithubGraphqlClient
import GithubGraphqlQueryable

@main struct GithubGraphqlExample {
	struct ProjectV2 {
		static let query = Node(type: "ProjectV2") {
			Field("title")
		}

		@Value var title: String
	}

	static func main() async throws{
		let privateKey: String = """
			-----BEGIN RSA PRIVATE KEY-----
			...
			-----END RSA PRIVATE KEY-----
			""" // Replace with your GitHub App's private key
		let client: GithubGraphqlClient = try await .init(
			appId: 123456, // Replace with your GitHub App ID
			privateKey: privateKey,
			installationLogin: "MPLew-is" // Replace with the user on which your app has been installed
		)

		let item = try await client.query(ProjectV2.self, id: "PVT_...") // Replace with the unique node ID for your GitHub Project (V2)
	}
}
```
(See [the GraphQL client example](./Examples/GithubProjectsGraphqlClient) for more detailed instructions on how to set up a GitHub app and get the required authentication/configuration values)


## Targets provided ##

- `GithubGraphqlQueryable`: a protocol and associated types for automatic query generation and decoding from a GraphQL JSON response

- `GithubApiClient`: a thin wrapper around [an `AsyncHTTPClient`](https://github.com/swift-server/async-http-client) which auto-injects the correct headers needed for the GitHub API, including the authentication needed for a GitHub App
	- You can use this by itself if you want to perform actions against the GitHub API other than query GraphQL objects (like in [the GitHub Actions Webhook example](./Examples/GithubActionsWebhookClient))

- `GithubGraphqlClient`: full client integrating the previous two targets into a simple interface for fetching and decoding a Swift object from a GraphQL server
