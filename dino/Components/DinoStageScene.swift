//
//  DinoStageScene.swift
//  dino
//
//  Atmospheric stage backdrop supporting custom static images, animated GIFs, and default lake backdrop.
//

import SwiftUI
import AppKit

struct DinoStageScene: View {
    let spaceColor: String
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(spaceColor: String = "blue") {
        self.spaceColor = spaceColor
    }

    private var customImage: NSImage? {
        let path = settings.customBackdropPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.page

                if let image = customImage {
                    let imgSize = image.size.width > 0 && image.size.height > 0 ? image.size : proxy.size
                    BackdropImageView(image: image, animates: !reduceMotion)
                        .id(settings.customBackdropPath)
                        .aspectRatio(imgSize, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image("DinoBackdrop")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.18), location: 0.0),
                        .init(color: Color.black.opacity(0.28), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.page)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Native NSImageView wrapper enabling hardware-accelerated animated GIF and image playback.
struct BackdropImageView: NSViewRepresentable {
    let image: NSImage
    var animates: Bool = true

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = animates
        view.canDrawSubviewsIntoLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image !== image {
            nsView.image = image
        }
        if nsView.animates != animates {
            nsView.animates = animates
        }
    }
}
