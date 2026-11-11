import CloveCore
import SwiftUI

/// Group-specific content inserted into detail's shared header and floating controls.
struct GroupReviewChrome {
    let group: BrowsingGroup
    let undecided: Int
    let undecidedOnly: Binding<Bool>
    let action: PillAction?
}
