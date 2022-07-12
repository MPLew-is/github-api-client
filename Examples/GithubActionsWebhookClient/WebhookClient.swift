import Foundation

import ArgumentParser
import AsyncHTTPClient
import Yams

import GithubApiClient


/// An object representing configuration values for the webhook client
struct WebhookClientConfiguration: Codable {
	/// GitHub App ID used to perform the webhook API call
	let appId: String
	/// GitHub App private key (PEM-encoded) used to perform the webhook API call
	let privateKey: String

	/// Name of user/organization the GitHub App is installed on, to fetch an installation access token
	let username: String

	/// Repository name on which the webhook API should be invoked
	let repository: String
	/// GitHub Actions webhook event type listened to by the workflow
	let eventType: String
}

@main
struct WebhookClient: AsyncParsableCommand {
	struct PayloadFile: LosslessStringConvertible, ExpressibleByArgument {
		let name: String
		var description: String { name }

		let handle: FileHandle

		init?(_ string: String) {
			if string == "-" {
				self.handle = .standardInput
			}
			else {
				guard let handle = FileHandle(forReadingAtPath: string) else {
					return nil
				}

				self.handle = handle
			}

			self.name = string
		}
	}


	@Option(name: [.customLong("config"), .short], help: "Path to config file to pull credentials and configuration information from")
	var configurationFile: String = "config.yaml"

	@Option(name: [.customLong("payload"), .short], help: "Path to file containing the JSON payload input for the GitHub Actions workflow, defaulting to standard input")
	var payloadFile: PayloadFile = .init("-")!


	func run() async throws {
		let configurationData: Data = try .init(contentsOf: .init(fileURLWithPath: configurationFile))
		let decoder = YAMLDecoder()
		let configuration = try decoder.decode(WebhookClientConfiguration.self, from: configurationData)

		let client: GithubApiClient = try await .init(
			appId: configuration.appId,
			privateKey: configuration.privateKey,
			installationLogin: configuration.username
		)


		// For this example, just wrap the input data with the configured event type without doing any other validation or processing.
		let prefix: String = """
			{"event_type":"\(configuration.eventType)","client_payload":
			"""
		let suffix: String = "}"
		var requestBody: Data = prefix.data(using: .utf8)!
		requestBody.append(try payloadFile.handle.readToEnd()!)
		requestBody.append(suffix.data(using: .utf8)!)

		var request: HTTPClientRequest = GithubApiEndpoint.repositoryDispatch(username: configuration.username, repository: configuration.repository).request
		request.body = .bytes(requestBody)

		let response = try await client.execute(request)

		guard response.status == .noContent else {
			print("Status: \(response.status)")

			let responseBody: Data = .init(buffer: try await response.body.collect(upTo: 10 * 1024))
			print("Body:")
			print(String(data: responseBody, encoding: .utf8)!)

			throw ExitCode.failure
		}
	}
}
