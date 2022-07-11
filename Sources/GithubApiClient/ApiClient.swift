import Foundation

import AsyncHTTPClient
import DeepCodable
import JWTKit
import NIOCore
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


	/**
	Generate a new authentication token with "current" issued-at and expiration times

	This actually returns an issued-at time one minute in the past, [as recommended in the GitHub documentation to allow for clock drift](https://docs.github.com/en/developers/apps/building-github-apps/authenticating-with-github-apps#authenticating-as-a-github-app).
	The expiration of the returned token will be 10 minutes from the issued-at time, the maximum allowable by the GitHub API

	- Parameter appId: GitHub App ID to be used as the issuer claim
	- Returns: New instance of an authentication token object, valid for ~9 minutes
	*/
	private static func generateAppTokenPayload(appId: String) -> AppAuthenticationToken {
		let issuedAt: Date = .init(timeIntervalSinceNow: -60)
		let expiration     = issuedAt + (10 * 60)
		return .init(
			issuedAt:   .init(rounding: issuedAt),
			expiration: .init(rounding: expiration),
			issuer:     .init(value: appId)
		)
	}


	/// Stored app-level authentication token payload
	private var appTokenPayload: AppAuthenticationToken

	/**
	Signed app authentication token

	For ease of use, this automatically refreshes the underlying token if it is no longer valid, but this means this access can throw if something fails during signing.
	*/
	private var appToken: String {
		get throws {
			if !self.appTokenPayload.isValid {
				self.appTokenPayload = Self.generateAppTokenPayload(appId: self.appId)
			}

			return try self.appTokenPayload.signed(using: self.signers)
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
	let httpClient: HTTPClient
	/// Whether this wrapper should shut down the HTTP client on `deinit`
	private let shouldShutdownHttpClient: Bool

	/// Container of signer objects with which to sign authentication tokens
	private let signers: JWTSigners

	/// Unique ID for the GitHub App this client is authenticating as an installation of
	private let appId: String
	/// Unique ID for the installation of a GitHub App this client is authenticating as
	let installationId: Int

	/**
	Initialize an instance, fetching the installation ID using the input login name.

	- Parameters:
		- appId: unique ID for the GitHub App this client is authenticating as an installation of
		- privateKey: PEM-encoded private key of the GitHub App, to authenticate as the app to the GitHub API
		- installationLogin: login name of the account the GitHub App has been installed on, and on whose resources the actual API calls will be made
		- httpClient: if not provided, the instance will create a new one and destroy it on `deinit`

	- Throws: `ClientError` if an error occurs during initial authentication; also rethrows any that happen from underlying HTTP/JWT/decoding operations
	*/
	public init(
		appId: String,
		privateKey: String,
		installationLogin: String,
		httpClient: HTTPClient? = nil
	) async throws {
		self.appId = appId

		self.signers = .init()

		let key = try RSAKey.private(pem: privateKey)
		self.signers.use(.rs256(key: key))


		if httpClient == nil {
			self.httpClient = HTTPClient(eventLoopGroupProvider: .createNew)
			self.shouldShutdownHttpClient = true
		}
		else {
			self.httpClient = httpClient!
			self.shouldShutdownHttpClient = false
		}


		self.appTokenPayload = Self.generateAppTokenPayload(appId: appId)
		let appToken = try self.appTokenPayload.signed(using: signers)

		var installationsRequest: HTTPClientRequest = GithubApiEndpoint.appInstallations.request
		installationsRequest.headers.add(name: "Authorization", value: "Bearer \(appToken)")
		installationsRequest.headers.add(name: "User-Agent",    value: Self.userAgent)
		installationsRequest.headers.add(name: "Accept",        value: Self.acceptType)

		let installationsResponse = try await self.httpClient.execute(installationsRequest, timeout: .seconds(10))
		let installationsBody = Data(buffer: try await installationsResponse.body.collect(upTo: 4 * 1024))
		let installations = try JSONDecoder().decode([InstallationResponse].self, from: installationsBody)

		let installation = installations.first { $0.login == installationLogin }
		guard let installation = installation else {
			throw ClientError.noMatchingInstallation
		}

		self.installationId = installation.id
	}

	deinit {
		if self.shouldShutdownHttpClient {
			try? httpClient.syncShutdown()
		}
	}


	/**
	Execute an input HTTP request, injecting the authentication token and other standard required inputs as additional headers.

	This method passes through to and from the same method on `AsyncHTTPClient.HTTPClient`, so see that method for more complete documentation.
	- See: `AsyncHTTPClient.HTTPClient.execute`

	- Parameters:
		- request: HTTP request object to be executed (after injecting any needed authentication/etc. headers)
		- timeout: timeout for completing the HTTP request

	- Returns: An `HTTPClientResponse` from the underlying `AsyncHTTPClient` implementation, representing the response to the input request
	- Throws: Only rethrows errors from the underlying `AsyncHTTPClient`/decoding calls
	*/
	public func execute(_ request: HTTPClientRequest, timeout: NIOCore.TimeAmount = .seconds(10)) async throws -> HTTPClientResponse {
		// We could cache the installation token until it expires, but as a first pass let's just grab a new one each time.
		var tokenRequest: HTTPClientRequest = GithubApiEndpoint.installationToken(installationId: self.installationId).request
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
}


/// Object representing a GitHub API endpoint, which can provide some generated values (like its method, URL, and pre-generated request objects)
public enum GithubApiEndpoint {
	/// GitHub API base URL, for centralization purposes
	public static let baseUrl: String = "https://api.github.com"


	/// https://docs.github.com/en/rest/apps/apps#list-installations-for-the-authenticated-app
	case appInstallations
	/// https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app
	case installationToken(installationId: Int)


	/// The HTTP method associated with the endpoint
	public var method: HTTPMethod {
		switch self {
			case .appInstallations:
				return .GET
			case .installationToken:
				return .POST
		}
	}

	/// The path component corresponding the endpoint
	public var path: String {
		switch self {
			case .appInstallations:
				return "app/installations"

			case .installationToken(let installationId):
				return "\(Self.appInstallations.path)/\(installationId)/access_tokens"
		}
	}

	/// The full URL corresponding to the endpoint
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
