import ClockKit
import SwiftUI

/// Watch face complication: 施錠状態をコンプリケーションとして表示する
final class ComplicationProvider: NSObject, CLKComplicationDataSource {

    private var connectivity: WatchConnectivityManager { .shared }

    // MARK: - Complication Descriptor

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptor = CLKComplicationDescriptor(
            identifier: "com.enablerdao.kacha.watchkitapp.lock",
            displayName: "KAGI 施錠状態",
            supportedFamilies: [
                .circularSmall,
                .modularSmall,
                .utilitarianSmall,
                .graphicCorner,
                .graphicCircular
            ]
        )
        handler([descriptor])
    }

    // MARK: - Timeline

    func getCurrentTimelineEntry(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
    ) {
        let isLocked = connectivity.isLocked
        let template = makeTemplate(for: complication.family, isLocked: isLocked)
        if let template {
            handler(CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template))
        } else {
            handler(nil)
        }
    }

    func getTimelineEndDate(
        for complication: CLKComplication,
        withHandler handler: @escaping (Date?) -> Void
    ) {
        handler(nil)
    }

    func getPrivacyBehavior(
        for complication: CLKComplication,
        withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
    ) {
        handler(.hideOnLockScreen)
    }

    // MARK: - Template Builder

    private func makeTemplate(
        for family: CLKComplicationFamily,
        isLocked: Bool
    ) -> CLKComplicationTemplate? {

        let lockImage = CLKImageProvider(
            onePieceImage: UIImage(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                ?? UIImage()
        )
        let statusText = CLKSimpleTextProvider(text: isLocked ? "施錠" : "解錠")
        let shortText = CLKSimpleTextProvider(text: isLocked ? "鍵" : "開")

        let fullColorImage = CLKFullColorImageProvider(
            fullColorImage: UIImage(systemName: isLocked ? "lock.fill" : "lock.open.fill") ?? UIImage()
        )

        switch family {
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallSimpleImage(imageProvider: lockImage)

        case .modularSmall:
            return CLKComplicationTemplateModularSmallSimpleImage(imageProvider: lockImage)

        case .utilitarianSmall:
            return CLKComplicationTemplateUtilitarianSmallFlat(
                textProvider: shortText,
                imageProvider: lockImage
            )

        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerTextImage(
                textProvider: statusText,
                imageProvider: fullColorImage
            )

        case .graphicCircular:
            return CLKComplicationTemplateGraphicCircularImage(imageProvider: fullColorImage)

        default:
            return nil
        }
    }
}
