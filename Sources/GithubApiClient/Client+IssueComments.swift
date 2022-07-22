import AsyncHTTPClient
import NIOFoundationCompat


public extension GithubApiClient {
	/**
	Create a comment on an issue using the input issue-comment URL.

	In general, any API calls/webhooks about an issue will include its comment URL as part of the body (often the `comments_url` value), so we can use that directly here.

	- Parameters:
		- url: issue-comment URL to use to post the new comment (should be in the format `https://api.github.com/repos/{Username}/{Repository}/issues/{Number}/comments`)
		- body: pre-constructed body representing the new issue comment
		- installationId: GitHub App installation ID that the API is being called on behalf of

	- Returns: An `HTTPClientResponse` representing the response to the comment-creation request
	- Throws: Only rethrows errors from the underlying `execute` call
	*/
	func createIssueComment(url: String, body: CreateIssueCommentRequest, for installationId: Int) async throws -> HTTPClientResponse {
		var request = HTTPClientRequest(url: url)
		request.method = .POST

		return try await self.execute(request, body: body, for: installationId)
	}

	/**
	Create a comment on an issue using the input issue-comment URL.

	In general, any API calls/webhooks about an issue will include its comment URL as part of the body (often the `comments_url` value), so we can use that directly here.

	- Parameters:
		- url: issue-comment URL to use to post the new comment (should be in the format `https://api.github.com/repos/{Username}/{Repository}/issues/{Number}/comments`)
		- body:
		GitHub-Flavored Markdown-formatted string of the comment to be created
		- installationId: GitHub App installation ID that the API is being called on behalf of

	- Returns: An `HTTPClientResponse` representing the response to the comment-creation request
	- Throws: Only rethrows errors from the underlying API calls (and any associated encoding/decoding)
	*/
	func createIssueComment(url: String, body: String, for installationId: Int) async throws -> HTTPClientResponse {
		let requestBody = CreateIssueCommentRequest(body: body)

		return try await self.createIssueComment(url: url, body: requestBody, for: installationId)
	}
}

/// Request body for [creating an issue comment](https://docs.github.com/en/rest/issues/comments#create-an-issue-comment)
public struct CreateIssueCommentRequest: Encodable {
	/// `body` parameter in request body for [creating an issue comment](https://docs.github.com/en/rest/issues/comments#create-an-issue-comment)
	public let body: String

	/**
	Initialize an instance from its component properties.

	- Parameter body: new issue comment body text (`body` parameter in request body for [creating an issue comment](https://docs.github.com/en/rest/issues/comments#create-an-issue-comment))
	*/
	public init(body: String) {
		self.body = body
	}
}


public extension GithubApiClient {
	/**
	Create an issue comment reaction on an issue using the input reaction URL.

	In general, any API calls/webhooks about an issue comment will include its reaction URL as part of the body (often the `reactions`.`url` value), so we can use that directly here.

	- Parameters:
		- url: reaction URL to use to post the new reaction (should be in the format `https://api.github.com/repos/{Username}/{Repository}/issues/{Issue number}/comments/{Issue comment ID}/reactions`)
		- body: pre-constructed body representing the new issue comment reaction
		- installationId: GitHub App installation ID that the API is being called on behalf of

	- Returns: An `HTTPClientResponse` representing the response to the comment-creation request
	- Throws: Only rethrows errors from the underlying `execute` call
	*/
	func createIssueCommentReaction(url: String, body: CreateIssueCommentReactionRequest, for installationId: Int) async throws -> HTTPClientResponse {
		var request = HTTPClientRequest(url: url)
		request.method = .POST

		return try await self.execute(request, body: body, for: installationId)
	}

	/**
	Create an issue comment reaction on an issue using the input reaction URL.

	In general, any API calls/webhooks about an issue comment will include its reaction URL as part of the body (often the `reactions`.`url` value), so we can use that directly here.

	- Parameters:
		- url: reaction URL to use to post the new reaction (should be in the format `https://api.github.com/repos/{Username}/{Repository}/issues/{Issue number}/comments/{Issue comment ID}/reactions`)
		- reaction: enum instance representing the reaction to create
		- installationId: GitHub App installation ID that the API is being called on behalf of

	- Returns: An `HTTPClientResponse` representing the response to the comment-creation request
	- Throws: Only rethrows errors from the underlying API calls (and any associated encoding/decoding)
	*/
	func createIssueCommentReaction(url: String, reaction: IssueCommentReaction, for installationId: Int) async throws -> HTTPClientResponse {
		let requestBody = CreateIssueCommentReactionRequest(content: reaction)

		return try await self.createIssueCommentReaction(url: url, body: requestBody, for: installationId)
	}
}


/// [Possible reactions to GitHub issue comments](https://docs.github.com/en/rest/reactions#about-the-reactions-api)
public enum IssueCommentReaction: String, Encodable {
	/// 👍
	case plusOne  = "+1"
	/// 👎
	case minusOne = "-1"
	/// 😄
	case laugh
	/// 😕
	case confused
	/// ❤️
	case heart
	/// 🎉
	case hooray
	/// 🚀
	case rocket
	/// 👀
	case eyes
}

/// Request body for [adding a reaction to an issue comment](https://docs.github.com/en/rest/reactions#create-reaction-for-an-issue-comment)
public struct CreateIssueCommentReactionRequest: Encodable {
	/// `content` parameter in request body for [adding a reaction to an issue comment](https://docs.github.com/en/rest/reactions#create-reaction-for-an-issue-comment)
	public let content: IssueCommentReaction

	/**
	Initialize an instance from its component properties.

	- Parameter content: new issue reaction choice (`content` parameter in request body for [adding a reaction to an issue comment](https://docs.github.com/en/rest/reactions#create-reaction-for-an-issue-comment))
	*/
	public init(content: IssueCommentReaction) {
		self.content = content
	}
}
