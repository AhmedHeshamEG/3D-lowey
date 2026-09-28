import SwiftUI

/// What every gesture does, in one quiet page: stage, Pencil, timeline, keyboard.
struct GestureGuide: View {
    @Environment(\.dismiss) private var dismiss

    struct Item: Identifiable {
        let symbol: String
        let gesture: String
        let result: String
        var id: String { gesture }
    }

    struct Section: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Stage", items: [
            Item(symbol: "hand.point.up.left", gesture: "Tap", result: "Select. Tap empty space to deselect"),
            Item(symbol: "hand.tap", gesture: "Long press", result: "Add to the selection"),
            Item(symbol: "hand.draw", gesture: "Drag", result: "Orbit the view. Drag a selected object to move it"),
            Item(symbol: "arrow.up.and.down.and.arrow.left.and.right", gesture: "Two-finger drag", result: "Pan"),
            Item(symbol: "arrow.up.left.and.arrow.down.right", gesture: "Pinch", result: "Zoom. Scales a selected overlay"),
            Item(symbol: "arrow.trianglehead.2.clockwise.rotate.90", gesture: "Two-finger twist",
                 result: "Roll the camera (Camera mode). Turns a selected overlay"),
            Item(symbol: "scope", gesture: "Double-tap", result: "Frame the selection"),
            Item(symbol: "arrow.uturn.backward", gesture: "Two-finger tap", result: "Undo"),
            Item(symbol: "arrow.uturn.forward", gesture: "Three-finger tap", result: "Redo"),
            Item(symbol: "rectangle.dashed", gesture: "Four-finger tap", result: "Hide or show the interface")
        ]),
        Section(title: "Apple Pencil", items: [
            Item(symbol: "pencil.tip", gesture: "Draw tool", result: "The Pencil draws; fingers keep moving the view"),
            Item(symbol: "scribble", gesture: "Draw, then hold", result: "Snaps the stroke to a clean line, circle, arc or rectangle"),
            Item(symbol: "pencil.and.outline", gesture: "Barrel roll (Pencil Pro)", result: "Turns the object while you perform"),
            Item(symbol: "circle.dotted", gesture: "Hover", result: "Preview where the Pencil lands (Scene menu, off by default)")
        ]),
        Section(title: "Timeline", items: [
            Item(symbol: "hand.point.up.left", gesture: "Tap or drag the ruler", result: "Move the playhead (snaps to words and keys)"),
            Item(symbol: "arrow.left.and.right", gesture: "Pinch", result: "Zoom time"),
            Item(symbol: "hand.draw", gesture: "Drag a bar or key", result: "Move it in time"),
            Item(symbol: "rectangle.dashed", gesture: "Long press, then drag", result: "Box-select keys"),
            Item(symbol: "flag", gesture: "Long press a marker", result: "Rename or delete it")
        ]),
        Section(title: "Keyboard", items: [
            Item(symbol: "space", gesture: "Space", result: "Play / pause"),
            Item(symbol: "command", gesture: "⌘Z  ⇧⌘Z", result: "Undo / redo"),
            Item(symbol: "command", gesture: "⌘D  ⌘C  ⌘V", result: "Duplicate, copy, paste"),
            Item(symbol: "command", gesture: "⌘G  ⌘A  ⌘⌫", result: "Group, select all, delete"),
            Item(symbol: "command", gesture: "⌘F", result: "Frame the selection"),
            Item(symbol: "command", gesture: "⌃⌘F", result: "Hide or show the interface"),
            Item(symbol: "command", gesture: "⌘K", result: "Key the selection at the playhead"),
            Item(symbol: "command", gesture: "⌘L", result: "Library"),
            Item(symbol: "option", gesture: "⌥←  ⌥→", result: "Step one frame"),
            Item(symbol: "option", gesture: "⌥⇧←  ⌥⇧→", result: "Nudge the selected keys one frame"),
            Item(symbol: "command", gesture: "⇧⌘R", result: "Record a performance (Animate)")
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Self.sections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title.uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Theme.secondaryText)
                                .padding(.bottom, 6)
                            ForEach(section.items) { item in
                                row(item)
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Gestures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("gestures-done")
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(item.gesture)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 190, alignment: .leading)
            Text(item.result)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
