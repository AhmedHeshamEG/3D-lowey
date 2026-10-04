import HmmDesign
import LoweyCore
import SwiftUI

/// The inspector, floating beside the selection without covering it (HmmFloatingPlacement): it keeps its side while
/// it fits, flips at the screen's edge, and glides over once the view settles. It stays inside the room the chrome
/// leaves: below the corner clusters, clear of the sidebar, an open panel and the bottom row.
struct FloatingInspector: View {
    let editor: EditorModel
    /// An open panel on the leading side, in screen space (the stage's space too: it fills the window from its corner).
    let avoiding: CGRect?
    let sidebarOnRight: Bool
    @State private var size: HmmPanelSize?
    @State private var side: HmmFloatingSide = .right
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The stage view ignores the top and side safe areas, so the selection's rect is in that space: so is this.
        GeometryReader { geometry in
            let placed = placement(in: geometry)
            InspectorPanel(editor: editor, size: $size)
                .environment(\.layoutDirection, layoutDirection)
                .frame(width: placed.frame.width, height: placed.frame.height)
                .position(x: placed.frame.midX, y: placed.frame.midY)
                .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: placed.frame)
                .onChange(of: placed.side) { _, newSide in side = newSide }
        }
        .environment(\.layoutDirection, .leftToRight)
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    private var panelSize: CGSize {
        CGSize(width: size?.width ?? InspectorPanel.defaultSize.width, height: size?.height ?? InspectorPanel.defaultSize.height)
    }

    private func placement(in geometry: GeometryProxy) -> HmmFloatingPlacement.Result {
        let room = Self.room(in: geometry.size, insets: geometry.safeAreaInsets, sidebarOnRight: sidebarOnRight, avoiding: avoiding)
        guard let target = editor.selectionScreenRect else {
            let frame = HmmFloatingPlacement.docked(panelSize, in: room, side: side)
            return HmmFloatingPlacement.Result(frame: frame, side: side, coverage: 0)
        }
        return HmmFloatingPlacement.place(panelSize, beside: target, in: room, current: side)
    }

    /// The part of the stage the inspector may use, clear of the chrome and of an open panel on either side.
    static func room(in size: CGSize, insets: EdgeInsets, sidebarOnRight: Bool, avoiding: CGRect?) -> CGRect {
        let margin = CGFloat(HmmSpacing.m)
        let sidebar: CGFloat = 64
        // A cluster's height and a gap above; the bottom row's height and a gap below.
        let band = CGFloat(HmmTarget.minimum + HmmSpacing.l)
        let top = insets.top + margin + band
        let bottom = size.height - margin - band
        var minX = insets.leading + margin + (sidebarOnRight ? 0 : sidebar)
        var maxX = size.width - insets.trailing - margin - (sidebarOnRight ? sidebar : 0)
        if let avoiding {
            // Leading is the left in left-to-right languages and the right in right-to-left ones.
            if avoiding.midX < size.width / 2 {
                minX = max(minX, avoiding.maxX + CGFloat(HmmSpacing.s))
            } else {
                maxX = min(maxX, avoiding.minX - CGFloat(HmmSpacing.s))
            }
        }
        return CGRect(x: minX, y: top, width: max(maxX - minX, 0), height: max(bottom - top, 0))
    }
}
