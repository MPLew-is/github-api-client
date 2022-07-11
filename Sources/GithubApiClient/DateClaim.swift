import Foundation

import JWTKit


extension Date {
	/**
	Create a new instance rounding this one to the nearest whole second.

	- Returns: A new `Date` instance rounded to the nearest whole second
	*/
	public func rounded() -> Self {
		return .init(timeIntervalSince1970: self.timeIntervalSince1970.rounded())
	}
}


/// Base protocol for date-related claims
protocol DateClaim {
	/**
	Initialize an instance from an input date value.

	- Parameter value: Date value representing the raw value for this date-related claim
	*/
	init(value: Date)
}

// Both date-related claims already implement what's needed for this protocol, so just conform them to it.
extension IssuedAtClaim: DateClaim {}
extension ExpirationClaim: DateClaim {}



// GitHub APIs don't like date claims with non-integer seconds, so add an initializer to date-based claims that will round input dates.
extension DateClaim {
	/**
	Initialize an instance from an input date value, rounding it to the nearest whole second.

	- Parameter value: Date value to round and use to initialize the new instance
	*/
	public init(rounding value: Date) {
		self.init(value: value.rounded())
	}
}
