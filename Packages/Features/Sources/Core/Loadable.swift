import Foundation
import StremioKit

/// Load state of one piece of remote data.
enum Loadable<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(AddonError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: AddonError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension Loadable: Equatable where Value: Equatable {}
