//
//  SplitGroup.swift
//  nomad
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

