import Foundation

#if os(iOS)
import UIKit
#endif

enum KeyboardHelper {
    static func dismiss() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        #endif
        // No-op on macOS — no software keyboard to dismiss
    }
}
