import Foundation

import AsyncHTTPClient
import NIOFoundationCompat

import GithubGraphqlQueryable


public extension GithubApiClient {
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
	Query the GitHub GraphQL API with the input request body.

	- Parameters:
		- body: raw query body object to be attached to the request
		- installationId: unique ID for the installation representing the account against which this query is being executed

	- Returns: An `HTTPClientResponse` representing the response to the input query object
	- Throws: Only rethrows errors from the underlying `execute` call
	*/
	func graphqlQuery(_ body: GraphqlRequest, for installationId: Int) async throws -> HTTPClientResponse {
		return try await self.execute(.graphql, body: body, for: installationId)
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
		let requestBody = GraphqlRequest(query: type.query(id: id))
		let response = try await self.graphqlQuery(requestBody, for: installationId)
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


/// [GraphQL request body](https://graphql.org/learn/serving-over-http/#post-request)
public struct GraphqlRequest: Encodable {
	/// `query` parameter in [the GraphQL request body](https://graphql.org/learn/serving-over-http/#post-request)
	public let query: String
	/// `variables` parameter in [the GraphQL request body](https://graphql.org/learn/serving-over-http/#post-request)
	public let variables: String?

	/**
	Initialize an instance from its component properties.

	- Parameters:
		- query: GraphQL query string (`query` parameter in [the GraphQL request body](https://graphql.org/learn/serving-over-http/#post-request))
		- variables: GraphQL variables string (`variables` parameter in [the GraphQL request body](https://graphql.org/learn/serving-over-http/#post-request))
	*/
	public init(query: String, variables: String? = nil) {
		self.query     = query
		self.variables = variables
	}
}
