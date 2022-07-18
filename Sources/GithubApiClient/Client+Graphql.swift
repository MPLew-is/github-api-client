import Foundation

import AsyncHTTPClient
import NIOFoundationCompat

import GithubGraphqlQueryable


public extension GithubApiClient {
	/// Helper struct representing the wrapped query for sending the GitHub API
	private struct GraphqlRequest: Encodable {
		let query: String
	}

	/// Object representing defined error cases in querying and decoding an object from the GraphQL API
	enum GraphqlError: Error {
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

	/**
	Query the GitHub GraphQL API, decoding the response into an instance of the input type.

	- Parameters:
		- type: type conforming to `GithubGraphqlQueryable` from which to generate the query body and to construct an instance of
		- id: node ID for the object being queried
		- installationId: unique ID for the installation representing the account against which this query is being executed

	- Returns: An instance of the input type, decoded from the GraphQL API response
	- Throws: `GraphqlError` for those defined error cases, also rethrows errors from the underlying HTTP client and encoding/decoding
	*/
	func graphqlQuery<Value: GithubGraphqlQueryable>(_ type: Value.Type, id: String, for installationId: Int) async throws -> Value {
		var request: HTTPClientRequest = GithubApiEndpoint.graphql.request

		let query = type.query(id: id)
		let requestBody: GraphqlRequest = .init(query: query)
		let requestBody_data = try JSONEncoder().encode(requestBody)
		request.body = .bytes(requestBody_data)

		let response = try await self.execute(request, for: installationId)
		guard response.status == .ok else {
			throw GraphqlError.httpError(response)
		}

		let responseBody_data: Data = .init(buffer: try await response.body.collect(upTo: 10 * 1024))

		do {
			let result = try JSONDecoder().decode(Value.self, from: responseBody_data)
			return result
		}
		catch {
			guard let responseBody = String(data: responseBody_data, encoding: .utf8) else {
				throw GraphqlError.characterSetError(responseBody_data)
			}

			throw GraphqlError.decodingError(responseBody)
		}
	}

	/**
	Query the GitHub GraphQL API, decoding the response into an instance of the input type.

	- Parameters:
		- type: type conforming to `GithubGraphqlQueryable` from which to generate the query body and to construct an instance of
		- id: node ID for the object being queried
		- installationLogin: username of the account against which this query is being executed

	- Returns: An instance of the input type, decoded from the GraphQL API response
	- Throws: `GraphqlError` for those defined error cases, also rethrows errors from the underlying HTTP client and encoding/decoding
	*/
	func graphqlQuery<Value: GithubGraphqlQueryable>(_ type: Value.Type, id: String, for installationLogin: String) async throws -> Value {
		let installationId = try await self.getInstallationId(login: installationLogin)
		return try await self.graphqlQuery(type, id: id, for: installationId)
	}
}
