import SwiftUI

extension View {
    /// Liquid Glass on macOS 26+, frosted material on earlier systems.
    /// Used for the floating chrome (zoom controls, focus exit button).
    @ViewBuilder
    func glassChrome<S: Shape>(in shape: S) -> some View {
        // #available guards the runtime; the compiler gate guards builds
        // on toolchains whose SDK predates glassEffect (e.g. CI runners)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }
}
