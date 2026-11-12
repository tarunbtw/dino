//
//  SplitGroup.swift
//  dino
//
//  Created by tarun on 10/11/26.
//

import Foundation

/// Which half of a split view a tab occupies.
public enum SplitSide: Sendable, Equatable {
    case left
    case right

    public var other: SplitSide {
        self == .left ? .right : .left
    }
}

/// Pair of tabs displayed side-by-side in Split View.
public struct SplitPair: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var leftTabId: UUID
    public var rightTabId: UUID
    public var ratio: Double // 0.2 ... 0.8, default 0.5

    public init(id: UUID = UUID(), leftTabId: UUID, rightTabId: UUID, ratio: Double = 0.5) {
        self.id = id
        self.leftTabId = leftTabId
        self.rightTabId = rightTabId
        self.ratio = min(0.8, max(0.2, ratio.isFinite ? ratio : 0.5))
    }

    public func contains(_ tabId: UUID) -> Bool {
        leftTabId == tabId || rightTabId == tabId
    }

    public func partner(of tabId: UUID) -> UUID? {
        if leftTabId == tabId { return rightTabId }
        if rightTabId == tabId { return leftTabId }
        return nil
    }

    public mutating func swap() {
        let temp = leftTabId
        leftTabId = rightTabId
        rightTabId = temp
    }
}

