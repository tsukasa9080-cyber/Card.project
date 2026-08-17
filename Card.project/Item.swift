//
//  Item.swift
//  Card.project
//
//  Created by G-2028 on 2026/08/18.
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
