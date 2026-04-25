//
//  Item.swift
//  timetracker
//
//  Created by gaozexuan on 2026/4/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
