//
//  LingoDexApp.swift
//  LingoDex
//
//  Created by Jia Yun Zhao on 2026-03-19.
//

import SwiftData
import SwiftUI

@main
struct LingoDexApp: App {
    static let modelContainer: ModelContainer = {
        do {
            let schema = Schema([CapturedWordEntity.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .modelContainer(Self.modelContainer)
        }
    }
}
