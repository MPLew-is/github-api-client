import Foundation

import AsyncHTTPClient
import NIOFoundationCompat

import GithubApiClient
import GithubGraphqlQueryable


/// Object providing a convenience wrapper around `GithubApiClient`, specifically for dealing with querying and decoding objects from GitHub's GraphQL API
public struct GithubGraphqlClient {
	/// Underlying client used to invoke the GitHub API
	public let client: GithubApiClient

	/**
	Initialize an instance, passing through parameters to the underlying `GithubApiClient` initializer.

	- Parameters:
		- appId: unique ID for the GitHub App this client is authenticating as an installation of
		- privateKey: PEM-encoded private key of the GitHub App, to authenticate as the app to the GitHub API
		- httpClient: if not provided, the instance will create a new one and destroy it on `deinit`

	- Throws: Only rethrows errors produced during `GithubApiClient` initialization
	*/
	public init(
		appId: String,
		privateKey: String,
		installationLogin: String,
		httpClient: HTTPClient? = nil
	) async throws {
		let client = try GithubApiClient(appId: appId, privateKey: privateKey, httpClient: httpClient)
		self.client = client
	}


	/// Helper struct representing the wrapped query for sending the GitHub API
	private struct GraphqlRequest: Encodable {
		let query: String
	}

	/**
	Query the GitHub GraphQL API, decoding the response into an instance of the input type.

	- Parameters:
		- type: type conforming to `GithubGraphqlQueryable` from which to generate the query body and to construct an instance of
		- id: node ID for the object being queried
		- installationId: unique ID for the installation representing the account against which this query is being executed

	- Returns: An instance of the input type, decoded from the GraphQL API response
	- Throws: `GithubGraphqlClientError` for those defined error cases, also rethrows errors from the underlying HTTP client and encoding/decoding
	*/
	public func query<Value: GithubGraphqlQueryable>(_ type: Value.Type, id: String, for installationId: Int) async throws -> Value {
		var request: HTTPClientRequest = GithubApiEndpoint.graphql.request

		let query = type.query(id: id)
		let requestBody: GraphqlRequest = .init(query: query)
		let requestBody_data = try JSONEncoder().encode(requestBody)
		request.body = .bytes(requestBody_data)

		let response = try await client.execute(request, for: installationId)
		guard response.status == .ok else {
			throw GithubGraphqlClientError.httpError(response)
		}

		let responseBody_data: Data = .init(buffer: try await response.body.collect(upTo: 10 * 1024))

		do {
			let result = try JSONDecoder().decode(Value.self, from: responseBody_data)
			return result
		}
		catch {
			guard let responseBody = String(data: responseBody_data, encoding: .utf8) else {
				throw GithubGraphqlClientError.characterSetError(responseBody_data)
			}

			throw GithubGraphqlClientError.decodingError(responseBody)
		}
	}

	/**
	Query the GitHub GraphQL API, decoding the response into an instance of the input type.

	- Parameters:
		- type: type conforming to `GithubGraphqlQueryable` from which to generate the query body and to construct an instance of
		- id: node ID for the object being queried
		- installationLogin: username of the account against which this query is being executed

	- Returns: An instance of the input type, decoded from the GraphQL API response
	- Throws: `GithubGraphqlClientError` for those defined error cases, also rethrows errors from the underlying HTTP client and encoding/decoding
	*/
	public func query<Value: GithubGraphqlQueryable>(_ type: Value.Type, id: String, for installationLogin: String) async throws -> Value {
		let installationId = try await self.client.getInstallationId(login: installationLogin)
		return try await self.query(type, id: id, for: installationId)
	}
}

/// Object representing defined error cases in querying and decoding an object from the GraphQL API
public enum GithubGraphqlClientError: Error {
	/**
	The GitHub API returned a non-OK response code

	The HTTP response object is attached to this case for further error handling or debugging.
	*/
	case httpError(HTTPClientResponse)

	/// During handling another error, the response body could not be decoded using UTF-8
	case characterSetError(Data)

	/**
	The input type could not be decoded from the response returned by the GitHub API

	The string of the returned body is attached to this case for further error handling or debugging.
	*/
	case decodingError(String)
}
