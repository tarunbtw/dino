//
//  BasecampLayout.swift
//  nomad
//
//  Arranges Basecamp tiles in balanced rows across the sidebar width.
//

import Foundation

public struct BasecampLayout: Equatable, Sendable {
    public let rows: [Int]
    public let tileWidth: Double

    public static let gap = 6.0
    public static let tileHeight = 40.0
    public static let minimumWidth = 52.0
    public static let maximumColumns = 4

    public init(rows: [Int], tileWidth: Double) {
        self.rows = rows
        self.tileWidth = tileWidth
    }

    public var height: Double {
        rows.isEmpty ? 0 : Double(rows.count) * Self.tileHeight + Double(rows.count - 1) * Self.gap
    }

    public static func make(
        count: Int,
        width: Double,
        maximumColumns: Int = maximumColumns,
        minimumWidth: Double = minimumWidth
    ) -> BasecampLayout {
        guard count > 0, width > 0 else { return BasecampLayout(rows: [], tileWidth: 0) }
        let fitting = Int((width + gap) / (minimumWidth + gap))
        let widest = min(max(fitting, 1), maximumColumns)
        let rowCount = (count + widest - 1) / widest
        let base = count / rowCount
        let extra = count % rowCount
        let rows = (0..<rowCount).map { base + ($0 < extra ? 1 : 0) }
        let columns = Double(rows[0])
        return BasecampLayout(rows: rows, tileWidth: (width - (columns - 1) * gap) / columns)
    }
}

