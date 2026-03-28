import SwiftUI
import WidgetKit

@main
struct KachaLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            KachaLiveActivity()
        }
    }
}
