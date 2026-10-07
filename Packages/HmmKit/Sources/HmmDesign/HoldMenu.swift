import Foundation

/// The hold menu, one grammar everywhere: touch and hold any thing (an object, a clip, a keyframe, a layer, a brush,
/// a card) and the same menu opens in the same order.
///
///     Duplicate · Rename · Copy · Paste
///     one to three extras that fit the thing
///     Delete (last, in red)
///
/// The four first rows and Delete are always there, in the same places: a row this kind of thing can't do is dimmed,
/// never missing, so the hand finds each row where it was on every other thing.
public struct HmmHoldMenu {
    /// One row.
    public struct Item: Identifiable {
        /// The title, unless rows could share one (names in a submenu).
        public var id: String
        public var title: String
        public var systemName: String
        public var isEnabled: Bool
        public var isDestructive: Bool
        /// The title is someone's own text (a name): shown as it is, never looked up in the String Catalog.
        public var isVerbatim: Bool
        /// A row with children opens a submenu instead of acting.
        public var children: [Item]
        public var action: @MainActor () -> Void

        public init(_ title: String, id: String? = nil, systemName: String = "", isEnabled: Bool = true, isDestructive: Bool = false,
                    isVerbatim: Bool = false, children: [Item] = [], action: @escaping @MainActor () -> Void = {}) {
            self.id = id ?? title
            self.title = title
            self.systemName = systemName
            self.isEnabled = isEnabled
            self.isDestructive = isDestructive
            self.isVerbatim = isVerbatim
            self.children = children
            self.action = action
        }

        fileprivate init(_ title: String, _ systemName: String, _ action: (@MainActor () -> Void)?, isDestructive: Bool = false) {
            self.init(title, systemName: systemName, isEnabled: action != nil, isDestructive: isDestructive, action: action ?? {})
        }
    }

    /// The most extras a menu shows; more than this belongs in a panel, not under a finger.
    public static let maximumExtras = 3
    /// The first rows of every hold menu, in order.
    public static let standardTitles = ["Duplicate", "Rename", "Copy", "Paste"]
    public static let deleteTitle = "Delete"

    public var duplicate: (@MainActor () -> Void)?
    public var rename: (@MainActor () -> Void)?
    public var copy: (@MainActor () -> Void)?
    public var paste: (@MainActor () -> Void)?
    public var extras: [Item]
    public var delete: (@MainActor () -> Void)?

    public init(duplicate: (@MainActor () -> Void)? = nil, rename: (@MainActor () -> Void)? = nil, copy: (@MainActor () -> Void)? = nil,
                paste: (@MainActor () -> Void)? = nil, extras: [Item] = [], delete: (@MainActor () -> Void)? = nil) {
        self.duplicate = duplicate
        self.rename = rename
        self.copy = copy
        self.paste = paste
        self.extras = extras
        self.delete = delete
    }

    /// The menu's rows, section by section (a divider between sections).
    public var sections: [[Item]] {
        let standard = [
            Item(Self.standardTitles[0], "plus.square.on.square", duplicate),
            Item(Self.standardTitles[1], "pencil", rename),
            Item(Self.standardTitles[2], "doc.on.doc", copy),
            Item(Self.standardTitles[3], "doc.on.clipboard", paste)
        ]
        let last = [Item(Self.deleteTitle, "trash", delete, isDestructive: true)]
        return [standard, Array(extras.prefix(Self.maximumExtras)), last].filter { !$0.isEmpty }
    }
}

#if canImport(SwiftUI)
    import SwiftUI

    /// A hold menu's rows, for `contextMenu` or a `Menu`.
    public struct HmmHoldMenuContent: View {
        private let menu: HmmHoldMenu

        public init(_ menu: HmmHoldMenu) {
            self.menu = menu
        }

        public var body: some View {
            let sections = menu.sections
            ForEach(sections.indices, id: \.self) { index in
                Section {
                    ForEach(sections[index]) { HmmHoldMenuRow(item: $0) }
                }
            }
        }
    }

    private struct HmmHoldMenuRow: View {
        let item: HmmHoldMenu.Item

        var body: some View {
            if item.children.isEmpty {
                Button(role: item.isDestructive ? .destructive : nil, action: item.action) { label }
                    .disabled(!item.isEnabled)
            } else {
                Menu {
                    ForEach(item.children) { HmmHoldMenuRow(item: $0) }
                } label: {
                    label
                }
                .disabled(!item.isEnabled)
            }
        }

        @ViewBuilder private var label: some View {
            let title = item.isVerbatim ? Text(verbatim: item.title) : Text(LocalizedStringKey(item.title))
            if item.systemName.isEmpty {
                title
            } else {
                Label { title } icon: { Image(systemName: item.systemName) }
            }
        }
    }

    public extension View {
        /// Touch and hold for this thing's menu, in the one grammar (`HmmHoldMenu`).
        func hmmHoldMenu(_ menu: @autoclosure @escaping () -> HmmHoldMenu) -> some View {
            contextMenu { HmmHoldMenuContent(menu()) }
        }
    }
#endif

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
    import UIKit

    public extension HmmHoldMenu {
        /// The same menu for UIKit (a canvas that isn't SwiftUI's: `HmmHoldMenuInteraction`).
        @MainActor
        func uiMenu() -> UIMenu {
            UIMenu(children: sections.map { UIMenu(options: .displayInline, children: $0.map(Self.element)) })
        }

        @MainActor
        private static func element(_ item: Item) -> UIMenuElement {
            let title = item.isVerbatim ? item.title : NSLocalizedString(item.title, comment: "")
            let image = item.systemName.isEmpty ? nil : UIImage(systemName: item.systemName)
            if !item.children.isEmpty {
                return UIMenu(title: title, image: image, children: item.children.map(element))
            }
            var attributes: UIMenuElement.Attributes = []
            if item.isDestructive { attributes.insert(.destructive) }
            if !item.isEnabled { attributes.insert(.disabled) }
            let action = item.action
            return UIAction(title: title, image: image, attributes: attributes) { _ in action() }
        }
    }

    /// The hold menu on a canvas: hold a finger still on a thing and its menu opens at the finger. If the finger
    /// moves first it's a drag, and the canvas' own gestures take it. `menu` says what is under a point (nil: nothing
    /// with a menu there).
    @MainActor
    public final class HmmHoldMenuInteraction: NSObject, UIContextMenuInteractionDelegate {
        private let menu: @MainActor (CGPoint) -> HmmHoldMenu?
        private var anchor: UIView?
        private var installed: UIContextMenuInteraction?

        public init(menu: @escaping @MainActor (CGPoint) -> HmmHoldMenu?) {
            self.menu = menu
        }

        public func install(on view: UIView) {
            uninstall()
            let interaction = UIContextMenuInteraction(delegate: self)
            view.addInteraction(interaction)
            installed = interaction
        }

        public func uninstall() {
            if let installed { installed.view?.removeInteraction(installed) }
            installed = nil
            anchor?.removeFromSuperview()
            anchor = nil
        }

        public func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                           configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let view = interaction.view, let menu = menu(location) else { return nil }
            placeAnchor(in: view, at: location)
            let built = menu.uiMenu()
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in built }
        }

        public func contextMenuInteraction(_: UIContextMenuInteraction, configuration _: UIContextMenuConfiguration,
                                           highlightPreviewForItemWithIdentifier _: any NSCopying) -> UITargetedPreview? {
            preview()
        }

        public func contextMenuInteraction(_: UIContextMenuInteraction, configuration _: UIContextMenuConfiguration,
                                           dismissalPreviewForItemWithIdentifier _: any NSCopying) -> UITargetedPreview? {
            preview()
        }

        public func contextMenuInteraction(_: UIContextMenuInteraction, willEndFor _: UIContextMenuConfiguration,
                                           animator: (any UIContextMenuInteractionAnimating)?) {
            let anchor = anchor
            self.anchor = nil
            if let animator {
                animator.addCompletion { MainActor.assumeIsolated { anchor?.removeFromSuperview() } }
            } else {
                anchor?.removeFromSuperview()
            }
        }

        /// The canvas itself must not lift or dim: the menu hangs from an invisible point under the finger.
        private func placeAnchor(in view: UIView, at location: CGPoint) {
            anchor?.removeFromSuperview()
            let point = UIView(frame: CGRect(x: location.x - 1, y: location.y - 1, width: 2, height: 2))
            point.backgroundColor = .clear
            point.isUserInteractionEnabled = false
            view.addSubview(point)
            anchor = point
        }

        private func preview() -> UITargetedPreview? {
            guard let anchor, anchor.window != nil else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.shadowPath = UIBezierPath()
            return UITargetedPreview(view: anchor, parameters: parameters)
        }
    }
#endif

#if canImport(UIKit) && canImport(SwiftUI) && !os(watchOS) && !os(tvOS)
    import SwiftUI

    /// The hold menu over an area SwiftUI draws as one picture (a timeline's lanes, a board): what's under the finger
    /// is known only by where the finger is. Lies behind the area, takes no touches itself, and listens from the
    /// window, so the area's own taps and drags work as before.
    public struct HmmHoldMenuArea: UIViewRepresentable {
        private let menu: @MainActor (CGPoint) -> HmmHoldMenu?

        public init(menu: @escaping @MainActor (CGPoint) -> HmmHoldMenu?) {
            self.menu = menu
        }

        public func makeUIView(context _: Context) -> MarkerView {
            let view = MarkerView()
            view.menu = menu
            view.isUserInteractionEnabled = false
            return view
        }

        public func updateUIView(_ view: MarkerView, context _: Context) {
            view.menu = menu
        }

        /// Marks the area's place on screen and moves the listener with its window.
        public final class MarkerView: UIView {
            var menu: (@MainActor (CGPoint) -> HmmHoldMenu?)?
            private var interaction: HmmHoldMenuInteraction?

            override public func didMoveToWindow() {
                super.didMoveToWindow()
                interaction?.uninstall()
                interaction = nil
                guard let window else { return }
                let interaction = HmmHoldMenuInteraction { [weak self, weak window] point in
                    guard let self, let window else { return nil }
                    let local = convert(point, from: window)
                    guard bounds.contains(local) else { return nil }
                    return menu?(local)
                }
                interaction.install(on: window)
                self.interaction = interaction
            }
        }
    }

    public extension View {
        /// Touch and hold anywhere on this view for the menu of what's at that point (in this view's own
        /// coordinates); nil where there's nothing with a menu.
        func hmmHoldMenu(at menu: @escaping @MainActor (CGPoint) -> HmmHoldMenu?) -> some View {
            background(HmmHoldMenuArea(menu: menu))
        }
    }
#endif
