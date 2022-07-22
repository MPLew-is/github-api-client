import Foundation

import AsyncHTTPClient
import DeepCodable
import JWTKit
import NIOCore
import NIOFoundationCompat
import NIOHTTP1


/// Object representing a GitHub App authentication token (which is a JWT)
internal struct AppAuthenticationToken: JWTPayload {
	/// The time that the token was issued at
	let issuedAt:   IssuedAtClaim
	/// The token's expiration
	let expiration: ExpirationClaim
	/// Identifier of the party that issued the token
	let issuer:     IssuerClaim

	/**
	Initialize an instance from its component properties.

	- Parameters:
		- issuedAt: time the token should store as its "issued-at" claim
		- expiration: time the token should store as its "expiration" claim
		- issuer: identifier of the party that issued the token
	*/
	internal init(
		issuedAt: IssuedAtClaim,
		expiration: ExpirationClaim,
		issuer: IssuerClaim
	) {
		self.issuedAt   = issuedAt
		self.expiration = expiration
		self.issuer     = issuer
	}


	private enum CodingKeys: String, CodingKey {
		case issuedAt   = "iat"
		case expiration = "exp"
		case issuer     = "iss"
	}

	// Abstracted base implementation for both `verify(using:)` and `isValid`
	private func verify() throws {
		try self.issuedAt.verifyNotIssuedInFuture()
		try self.expiration.verifyNotExpired()
	}

	internal func verify(using _: JWTSigner) throws {
		try self.verify()
	}

	/// Whether the token is still valid, by validating the various claims stored
	internal var isValid: Bool {
		(try? self.verify()) != nil
	}


	/// Cache for the signed string generated from this token
	private var signed: String? = nil

	/**
	Return a signed representation of this token, using the input signers

	For performance, this will return a cached value if the token has been signed before.
	This cache is not (yet) keyed by the `signers`, so in order to change the signers and get a validly signed token, a new instance should be created.

	- Parameter signers: container of signers to use to sign this token
	- Returns: Signed representation of the claims made in this token
	- Throws: Only rethrows any signing errors from `JWTSigners`
	*/
	mutating internal func signed(using signers: JWTSigners) throws -> String {
		if self.signed == nil {
			self.signed = try signers.sign(self)
		}

		return self.signed!
	}
}


/// Object representing the fields we care about in the API response from requesting installations for an app
internal struct InstallationResponse: DeepDecodable {
	@Value var id: Int
	@Value var login: String

	static let codingTree = CodingTree {
		Key("id", containing: \._id)

		Key("account") {
			Key("login", containing: \._login)
		}
	}
}

/// Object representing the fields we care about in the response from requesting an installation token
internal struct InstallationTokenResponse: Decodable, LosslessStringConvertible {
	let token: String


	init?(_ description: String) {
		self.token = description
	}

	var description: String { self.token }
}


/**
Object representing a single installation of a GitHub App, handling the authentication needed to make calls as that installation

This must be a class since we want `deinit` behavior for automatic shutdown of the wrapped client.
*/
public class GithubApiClient {
	/// The user agent for HTTP requests (required by the GitHub API), for centralization purposes
	private static let userAgent:  String = "swift-server/async-http-client"
	/// The `Accept` header value for HTTP requests (required by the GitHub API), for centralization purposes
	private static let acceptType: String = "application/vnd.github.v3+json"


	/// Stored app-level authentication token payload
	private var appTokenPayload: AppAuthenticationToken?

	/**
	Signed app authentication token

	For ease of use, this automatically refreshes the underlying token if it is no longer valid, but this means this access can throw if something fails during signing.
	*/
	private var appToken: String {
		get throws {
			if self.appTokenPayload == nil || !self.appTokenPayload!.isValid {
				let issuedAt: Date = .init(timeIntervalSinceNow: -60)
				let expiration     = issuedAt + (10 * 60)
				self.appTokenPayload = .init(
					issuedAt:   .init(rounding: issuedAt),
					expiration: .init(rounding: expiration),
					issuer:     .init(value: self.appId)
				)
			}

			return try self.appTokenPayload!.signed(using: self.signers)
		}
	}


	/// Error type representing usage errors by users of this client
	public enum ClientError: String, Error {
		/// No installation was found that matched the input login name; app is likely not installed
		case noMatchingInstallation = """
			No installation matching the input login name was found - is your GitHub App installed on your account?
			For more help, see: https://docs.github.com/en/developers/apps/managing-github-apps/installing-github-apps#installing-your-private-github-app-on-your-repository
			"""
	}


	/// Stored async HTTP client object, either auto-created or input by the user
	private let httpClient: HTTPClient
	/// Whether this wrapper should shut down the HTTP client on `deinit`
	private let shouldShutdownHttpClient: Bool

	/// Container of signer objects with which to sign authentication tokens
	private let signers: JWTSigners

	/// Unique ID for the GitHub App this client is authenticating as an installation of
	private let appId: String

	/**
	Initialize an instance, fetching the installation ID using the input login name.

	- Parameters:
		- appId: unique ID for the GitHub App this client is authenticating as an installation of
		- privateKey: PEM-encoded private key of the GitHub App, to authenticate as the app to the GitHub API
		- httpClient: if not provided, the instance will create a new one and destroy it on `deinit`

	- Throws: Only rethrows any that happen from underlying HTTP/JWT/decoding operations
	*/
	public init(
		appId: String,
		privateKey: String,
		httpClient: HTTPClient? = nil
	) throws {
		self.appId = appId

		self.signers = .init()

		let key = try RSAKey.private(pem: privateKey)
		self.signers.use(.rs256(key: key))


		if httpClient == nil {
			self.httpClient = .init(eventLoopGroupProvider: .createNew)
			self.shouldShutdownHttpClient = true
		}
		else {
			self.httpClient = httpClient!
			self.shouldShutdownHttpClient = false
		}
	}

	deinit {
		if self.shouldShutdownHttpClient {
			try? httpClient.syncShutdown()
		}
	}


	/**
	Get a unique installation ID from the input installation login username.

	This has to be a special method rather than a normal call to `execute` since this only authenticates with the app token, and the user may not even know their installation ID until making this call.

	- Parameter login: GitHub username that this app was installed on
	- Returns: integer installation ID to use for future calls to `execute`
	- Throws: `ClientError` if an error occurs during initial authentication; also rethrows any that happen from underlying HTTP/JWT/decoding operations
	*/
	public func getInstallationId(login: String) async throws -> Int {
		var installationsRequest: HTTPClientRequest = GithubApiEndpoint.appInstallations.request
		installationsRequest.headers.add(name: "Authorization", value: "Bearer \(try self.appToken)")
		installationsRequest.headers.add(name: "User-Agent",    value: Self.userAgent)
		installationsRequest.headers.add(name: "Accept",        value: Self.acceptType)

		let installationsResponse = try await self.httpClient.execute(installationsRequest, timeout: .seconds(10))
		let installationsBody = Data(buffer: try await installationsResponse.body.collect(upTo: 4 * 1024))
		let installations = try JSONDecoder().decode([InstallationResponse].self, from: installationsBody)

		let installation = installations.first { $0.login == login }
		guard let installation = installation else {
			throw ClientError.noMatchingInstallation
		}

		return installation.id
	}


	/**
	Execute an input HTTP request, injecting the authentication token and other standard required inputs as additional headers.

	This method passes through to and from the same method on `AsyncHTTPClient.HTTPClient`, so see that method for more complete documentation.
	- See: `AsyncHTTPClient.HTTPClient.execute`

	- Parameters:
		- request: HTTP request object to be executed (after injecting any needed authentication/etc. headers)
		- installationId: GitHub App installation ID that the API is being called on behalf of
		- timeout: timeout for completing the HTTP request

	- Returns: An `HTTPClientResponse` from the underlying `AsyncHTTPClient` implementation, representing the response to the input request
	- Throws: Only rethrows errors from the underlying `AsyncHTTPClient`/decoding calls
	*/
	public func execute(_ request: HTTPClientRequest, for installationId: Int, timeout: NIOCore.TimeAmount = .seconds(10)) async throws -> HTTPClientResponse {
		// We could cache the installation token until it expires, but as a first pass let's just grab a new one each time.
		var tokenRequest: HTTPClientRequest = GithubApiEndpoint.installationToken(installationId: installationId).request
		tokenRequest.headers.add(name: "Authorization", value: "Bearer \(try self.appToken)")
		tokenRequest.headers.add(name: "User-Agent",    value: Self.userAgent)
		tokenRequest.headers.add(name: "Accept",        value: Self.acceptType)

		let tokenResponse = try await self.httpClient.execute(tokenRequest, timeout: timeout)
		let tokenResponseBody = Data(buffer: try await tokenResponse.body.collect(upTo: 4 * 1024))
		let installationToken = try JSONDecoder().decode(InstallationTokenResponse.self, from: tokenResponseBody)


		var modifiedRequest = request
		modifiedRequest.headers.add(name: "Authorization", value: "token \(installationToken)")
		modifiedRequest.headers.add(name: "User-Agent",    value: Self.userAgent)
		modifiedRequest.headers.add(name: "Accept",        value: Self.acceptType)

		return try await self.httpClient.execute(modifiedRequest, timeout: timeout)
	}

	/**
	Execute an input HTTP request, attaching a pre-encoded `Data` instance as the body.

	This simply attaches the body and passes the request down to `execute(_:for:timeout:)`, so see that method for more information.

	- Parameters:
		- request: HTTP request object to be executed (after attaching an encoded body)
		- body: already-encoded `Data` for the request body
		- installationId: GitHub App installation ID that the API is being called on behalf of
		- timeout: timeout for completing the HTTP request

	- Returns: An `HTTPClientResponse` from the underlying `AsyncHTTPClient` implementation, representing the response to the input request
	- Throws: Only rethrows errors from the underlying `AsyncHTTPClient`/encoding/decoding calls
	*/
	public func execute(_ request: HTTPClientRequest, body: Data, for installationId: Int, timeout: NIOCore.TimeAmount = .seconds(10)) async throws -> HTTPClientResponse {
		var modifiedRequest = request
		modifiedRequest.body = .bytes(body)

		return try await self.execute(modifiedRequest, for: installationId, timeout: timeout)
	}

	/**
	Execute an input HTTP request, auto-encoding an encodable body for convenience.

	This simply encodes the body and passes the request down to `execute(_:body:for::timeout:)`, so see that method for more information.

	- Parameters:
		- request: HTTP request object to be executed (after attaching an encoded body)
		- body: instance of encodable type to attach to the request
		- installationId: GitHub App installation ID that the API is being called on behalf of
		- timeout: timeout for completing the HTTP request

	- Returns: An `HTTPClientResponse` from the underlying `AsyncHTTPClient` implementation, representing the response to the input request
	- Throws: Only rethrows errors from the underlying `AsyncHTTPClient`/encoding/decoding calls
	*/
	public func execute<Body: Encodable>(_ request: HTTPClientRequest, body: Body, for installationId: Int, timeout: NIOCore.TimeAmount = .seconds(10)) async throws -> HTTPClientResponse {
		let body_data = try JSONEncoder().encode(body)
		return try await self.execute(request, body: body_data, for: installationId, timeout: timeout)
	}

	/**
	Execute the request corresponding to an input endpoint, auto-encoding an encodable body for convenience.

	This simply gets the corresponding request object and passes it down to `execute(_:body:for:timeout:)`, so see that method for more information.

	- Parameters:
		- endpoint: GitHub API endpoint to execute (after attaching an encoded body)
		- body: instance of encodable type to attach to the request
		- installationId: GitHub App installation ID that the API is being called on behalf of
		- timeout: timeout for completing the HTTP request

	- Returns: An `HTTPClientResponse` from the underlying `AsyncHTTPClient` implementation, representing the response to the input request
	- Throws: Only rethrows errors from the underlying `AsyncHTTPClient`/encoding/decoding calls
	*/
	public func execute<Body: Encodable>(_ endpoint: GithubApiEndpoint, body: Body, for installationId: Int, timeout: NIOCore.TimeAmount = .seconds(10)) async throws -> HTTPClientResponse {
		return try await self.execute(endpoint.request, body: body, for: installationId, timeout: timeout)
	}
}


/// Object representing a GitHub API endpoint, which can provide some generated values (like its method, URL, and pre-generated request objects)
public enum GithubApiEndpoint {
	/// GitHub API base URL, for centralization purposes
	public static let baseUrl: String = "https://api.github.com"


	/// [List installations for the authenticated app](https://docs.github.com/en/rest/apps/apps#list-installations-for-the-authenticated-app)
	case appInstallations
	/// [Create an installation access token for an app](https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app)
	case installationToken(installationId: Int)
	/// [Create a workflow dispatch event](https://docs.github.com/en/rest/actions/workflows#create-a-workflow-dispatch-event)
	case repositoryDispatch(username: String, repository: String)
	/// [Query the GraphQL API](https://docs.github.com/en/graphql/guides/forming-calls-with-graphql)
	case graphql


	/// HTTP method associated with the endpoint
	public var method: HTTPMethod {
		switch self {
			case .appInstallations:
				return .GET
			case .installationToken, .repositoryDispatch, .graphql:
				return .POST
		}
	}

	/// Path component corresponding the endpoint
	public var path: String {
		switch self {
			case .appInstallations:
				return "app/installations"

			case .installationToken(let installationId):
				return "\(Self.appInstallations.path)/\(installationId)/access_tokens"

			case .repositoryDispatch(let username, let repository):
				return "repos/\(username)/\(repository)/dispatches"

			case .graphql:
				return "graphql"
		}
	}

	/// Full URL corresponding to the endpoint
	public var url: String {
		return "\(Self.baseUrl)/\(self.path)"
	}

	/// A new request object pre-configured for the given endpoint
	public var request: HTTPClientRequest {
		var request = HTTPClientRequest(url: self.url)
		request.method = self.method
		return request
	}
}
