//
//  Item.swift
//  takout-photos-fixer
//
//  Created by Amit Rathiesh on 2025-11-23.
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
