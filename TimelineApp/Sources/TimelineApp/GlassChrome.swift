import SwiftUI

extension View {
    /// Liquid Glass on macOS 26+, frosted material on earlier systems.
    /// Used for the floating chrome (zoom controls, focus exit button).
    @ViewBuilder
    func glassChrome<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
