import HmmDesign
import LoweyCore
import SwiftUI

/// Preferences: appearance, feel, the stage, storage.
struct PreferencesForm: View {
    let app: AppModel
    @AppStorage(HmmThemeMode.storageKey) private var themeMode = HmmThemeMode.dark.rawValue
    @AppStorage(HmmHaptics.storageKey) private var haptics = true
    @AppStorage(AppSettings.sidebarOnRight) private var sidebarOnRight = false
    @AppStorage(AppSettings.pencilHoverPreview) private var pencilHover = false
    @AppStorage(HmmPencilOrHand.fingersAlwaysMakeKey) private var fingersMake = false
    @AppStorage(AppSettings.fullResolutionStage) private var fullResolution = false
    @AppStorage(AppSettings.inspectorDocked) private var inspectorDocked = false
    @AppStorage(AppSettings.navigationSpeed) private var navigationSpeed = 1.0
    @AppStorage(AppSettings.showsJoystick) private var showsJoystick = true
    @AppStorage(AppSettings.joystickSpeed) private var joystickSpeed = 1.0
    @AppStorage(AppSettings.storeInICloud) private var iCloud = true

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themeMode) {
                ForEach(HmmThemeMode.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
            }
            Toggle("Sidebar on the right (left-handed)", isOn: $sidebarOnRight)
            Toggle("Haptics", isOn: $haptics)
        }
        Section {
            Toggle("Draw with a finger too", isOn: $fingersMake)
                .accessibilityIdentifier("settings-fingers-make")
        } header: {
            Text("Pencil or hand")
        } footer: {
            Text("One finger draws until an Apple Pencil touches the screen. Then the Pencil draws and fingers move the view, unless this is on.")
        }
        Section("Stage") {
            Toggle("Pencil hover preview", isOn: $pencilHover)
            Toggle("Always full resolution", isOn: $fullResolution)
            LabeledSlider(title: "Moving around (orbit, pan, zoom)", value: navigationSpeed, range: AppSettings.navigationSpeedRange,
                          format: { String(format: "%.2g×", $0) }) { navigationSpeed = $0 }
            Toggle("Dock the inspector at the side", isOn: $inspectorDocked)
                .accessibilityIdentifier("settings-inspector-docked")
            Toggle("Joystick under a selection", isOn: $showsJoystick)
                .accessibilityIdentifier("settings-joystick")
            if showsJoystick {
                LabeledSlider(title: "Joystick speed", value: joystickSpeed, range: AppSettings.joystickSpeedRange,
                              format: { String(format: "%.2g×", $0) }) { joystickSpeed = $0 }
            }
        }
        Section {
            Toggle("Keep projects in iCloud Drive", isOn: Binding(get: { iCloud }, set: { value in
                iCloud = value
                Task { await app.setStoresInICloud(value) }
            }))
        } header: {
            Text("Storage")
        } footer: {
            Text(app.storage.isICloud ? "Your projects sync between your devices and show in Files."
                : "Projects are on this iPad (in Files ▸ On My iPad). iCloud Drive needs the App Store version and an iCloud account.")
        }
    }
}

/// About, licences and acknowledgements.
struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: AppIdentity.version)
            LabeledContent("Made by", value: "studio h.")
            NavigationLink("Licences") { AcknowledgementsView() }
            Text("No account, no tracking: nothing leaves this iPad unless you share it.").font(.hmm(.footnote))
        }
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                Text("CMU Pronouncing Dictionary").font(.hmm(.headline, weight: .semibold))
                Text("Used for lip sync. Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved. "
                    + "Redistribution and use in source and binary forms, with or without modification, are permitted provided that the copyright notice, "
                    + "this list of conditions and the following disclaimer are kept. THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY \"AS IS\" "
                    + "AND ANY EXPRESSED OR IMPLIED WARRANTIES ARE DISCLAIMED.")
                    .font(.hmm(.footnote))
                Text("Manifold").font(.hmm(.headline, weight: .semibold))
                Text("Booleans on solids (union, subtract, intersect). Copyright The Manifold Authors. Apache License 2.0.")
                    .font(.hmm(.footnote))
                Text("xatlas").font(.hmm(.headline, weight: .semibold))
                Text("Lays models flat so they can be painted. Copyright (c) 2018-2020 Jonathan Young; thekla_atlas copyright (c) 2013 Thekla, Inc "
                    + "and NVIDIA Corporation. MIT License: permission is granted, free of charge, to use, copy, modify and distribute it, provided "
                    + "the copyright and permission notices are kept. It is provided \"as is\", without warranty of any kind.")
                    .font(.hmm(.footnote))
                Text("The Kit").font(.hmm(.headline, weight: .semibold))
                Text("The models in the Library's Sets come from Kenney (kenney.nl: Furniture, Food, Nature, City, Car, Space, Survival and "
                    + "Mini Market kits) and Quaternius (quaternius.com: Sci-Fi Essentials, Universal Base Characters, Universal Animation "
                    + "Library). They are released under CC0 1.0 (public domain); we credit them because they deserve it.")
                    .font(.hmm(.footnote))
                Text("Everything else in \(AppIdentity.displayName) (the renderer, the glTF reader, the characters) is our own code.")
                    .font(.hmm(.footnote))
            }
            .padding(HmmSpacing.l)
        }
        .navigationTitle("Licences")
    }
}

/// Every gesture, the same in every hmm. app, plus Maquette's own.
struct GestureGuide: View {
    struct Item: Identifiable {
        let symbol: String
        let gesture: String
        let result: String
        var id: String { gesture }
    }

    static let sections: [(String, [Item])] = [
        ("Everywhere", HmmUniversalGesture.allCases.map { Item(symbol: "hand.tap", gesture: $0.gesture, result: $0.meaning) }),
        ("Stage", [
            Item(symbol: "hand.point.up.left", gesture: "Tap", result: "Select; tap empty space to deselect"),
            Item(symbol: "hand.draw", gesture: "Drag", result: "Orbit; drag the selection to move it"),
            Item(symbol: "arrow.up.and.down.and.arrow.left.and.right", gesture: "Two-finger drag", result: "Pan"),
            Item(symbol: "arrow.trianglehead.2.clockwise.rotate.90", gesture: "Two fingers on the selection", result: "Twist turns it, pinch sizes it"),
            Item(symbol: "scope", gesture: "Double-tap", result: "Frame the selection"),
            Item(symbol: "hand.tap", gesture: "Touch and hold an object", result: "Add it to the selection"),
            Item(symbol: "video", gesture: "Director view", result: "Fingers fly the shot camera: drag aims, two fingers move, pinch dollies, twist rolls")
        ]),
        ("Apple Pencil", [
            Item(symbol: "pencil.tip", gesture: "A drawing or painting tool", result: "The Pencil makes, fingers move the view. No Pencil: a finger makes"),
            Item(symbol: "scribble", gesture: "Draw, then hold", result: "Snaps to a clean line, circle or rectangle"),
            Item(symbol: "pencil.and.outline", gesture: "Squeeze (Pencil Pro)", result: "Play / pause"),
            Item(symbol: "arrow.clockwise", gesture: "Barrel roll (Pencil Pro)", result: "Turns what you perform")
        ]),
        ("Timeline", [
            Item(symbol: "hand.point.up.left", gesture: "Tap or drag the ruler", result: "Move the playhead (snaps to words)"),
            Item(symbol: "arrow.left.and.right", gesture: "Pinch", result: "Zoom time"),
            Item(symbol: "rectangle.dashed", gesture: "Touch and hold, then drag", result: "Box-select keys"),
            Item(symbol: "flag", gesture: "Touch and hold a marker", result: "Rename or delete it")
        ]),
        ("Keyboard", [
            Item(symbol: "space", gesture: "Space · J K L", result: "Play / pause · shuttle"),
            Item(symbol: "option", gesture: "⌥← ⌥→", result: "Back / forward 10 seconds"),
            Item(symbol: "command", gesture: "⌘1 – ⌘5", result: "Select, Build, Draw, Transform, Look"),
            Item(symbol: "command", gesture: "⌘Z ⇧⌘Z ⌘D ⌘G ⌘K", result: "Undo, redo, duplicate, group, key"),
            Item(symbol: "questionmark", gesture: "?", result: "This page")
        ])
    ]

    var body: some View {
        List {
            ForEach(Self.sections, id: \.0) { section in
                Section(section.0) {
                    ForEach(section.1) { item in
                        HStack(spacing: HmmSpacing.s) {
                            Image(systemName: item.symbol).foregroundStyle(Color.accentColor).frame(width: 28)
                            Text(item.gesture).font(.hmm(.body, weight: .semibold)).frame(width: 220, alignment: .leading)
                            Text(item.result).font(.hmm(.body)).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Gestures")
    }
}
