import Foundation

import JWTKit


// The expiration claim has a verify function for its date value (`ExpirationClaim.verifyNotExpired`), let's also make sure the issued-at claim has guardrails.
extension IssuedAtClaim {
	/**
	Throws an error if the claim's date is later than the current date, with a minute of buffer to account for clock drift.

	- Parameter currentDate: current date to compare against, defaulting to now
	- Throws: `JWTError.claimVerificationFailure` if verification fails
	*/
	public func verifyNotIssuedInFuture(currentDate: Date = .init()) throws {
		let minuteIntoFuture: Date = currentDate + TimeInterval(60)

		if self.value > minuteIntoFuture {
			throw JWTError.claimVerificationFailure(name: "iat", reason: "Issued in the future, even allowing for 60 seconds of clock drift")
		}
	}
}
