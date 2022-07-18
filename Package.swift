// swift-tools-version: 5.6

import PackageDescription

let package = Package(
	name: "GithubGraphqlClient",
	platforms: [
		.macOS(.v11),
	],
	products: [
		.library(
			name: "GithubApiClient",
			targets: ["GithubApiClient"]
		),
		.library(
			name: "GithubGraphqlQueryable",
			targets: ["GithubGraphqlQueryable"]
		),
	],
	dependencies: [
		.package(url: "https://github.com/apple/swift-argument-parser", from: "1.1.0"),
		.package(url: "https://github.com/swift-server/async-http-client", from: "1.11.0"),
		.package(url: "https://github.com/MPLew-is/deep-codable", branch: "main"),
		.package(url: "https://github.com/vapor/jwt-kit", from: "4.0.0"),
		.package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
	],
	targets: [
		.target(
			name: "GithubApiClient",
			dependencies: [
				"GithubGraphqlQueryable",
				.product(name: "AsyncHTTPClient", package: "async-http-client"),
				.product(name: "DeepCodable", package: "deep-codable"),
				.product(name: "JWTKit", package: "jwt-kit"),
			]
		),
		.executableTarget(
			name: "GithubActionsWebhookClient",
			dependencies: [
				"GithubApiClient",
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "AsyncHTTPClient", package: "async-http-client"),
				.product(name: "Yams", package: "Yams"),
			],
			path: "Examples/GithubActionsWebhookClient",
			exclude: [
				"ReadMe.md",
				"example-workflow-light.png",
				"example-workflow-dark.png",
				"config.yaml",
				"config.example.yaml",
				"print-payload.yaml",
				"payload.example.json",
			]
		),
		.target(
			name: "GithubGraphqlQueryable",
			dependencies: [
				.product(name: "DeepCodable", package: "deep-codable"),
			]
		),
		.testTarget(
			name: "GithubGraphqlQueryableTests",
			dependencies: ["GithubGraphqlQueryable"]
		),
		.executableTarget(
			name: "GithubProjectsGraphqlClient",
			dependencies: [
				"GithubApiClient",
				"GithubGraphqlQueryable",
				.product(name: "ArgumentParser", package: "swift-argument-parser"),
				.product(name: "AsyncHTTPClient", package: "async-http-client"),
				.product(name: "Yams", package: "Yams"),
			],
			path: "Examples/GithubProjectsGraphqlClient",
			exclude: [
				"ReadMe.md",
				"example-output-light.png",
				"example-output-dark.png",
				"config.yaml",
				"config.example.yaml",
			]
		),
	]
)
