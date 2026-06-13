//
//  Item.swift
//  MyPhone
//
//  Created by Emre Yurtseven on 13.06.26.
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
