import SwiftUI

/// The handoff's group pill, shared by grid and filmstrip stacks (components.md).
struct GroupCountBadge: View {
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(.system(size: 11, weight: .bold))
            // The handoff has no on-group token; white is invariant across all themes.
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.clove.group, in: RoundedRectangle(cornerRadius: 8))
    }
}
