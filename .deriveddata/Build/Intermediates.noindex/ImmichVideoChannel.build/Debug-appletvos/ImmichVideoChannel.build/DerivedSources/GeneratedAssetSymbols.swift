import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = ColorResource(name: "AccentColor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "App Icon" asset catalog resource namespace.
    enum AppIcon {

        /// The "App Icon/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon/Front/Content" asset catalog image resource.
            static let content = ImageResource(name: "App Icon/Front/Content", bundle: resourceBundle)

        }

        /// The "App Icon/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon/Back/Content" asset catalog image resource.
            static let content = ImageResource(name: "App Icon/Back/Content", bundle: resourceBundle)

        }

        /// The "App Icon/Middle" asset catalog resource namespace.
        enum Middle {

            /// The "App Icon/Middle/Content" asset catalog image resource.
            static let content = ImageResource(name: "App Icon/Middle/Content", bundle: resourceBundle)

        }

    }

    /// The "App Icon - App Store" asset catalog resource namespace.
    enum AppIconAppStore {

        /// The "App Icon - App Store/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon - App Store/Front/Content" asset catalog image resource.
            @available(watchOS, unavailable)
            static let content = ImageResource(thinnableName: "App Icon - App Store/Front/Content", bundle: resourceBundle)

        }

        /// The "App Icon - App Store/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon - App Store/Back/Content" asset catalog image resource.
            @available(watchOS, unavailable)
            static let content = ImageResource(thinnableName: "App Icon - App Store/Back/Content", bundle: resourceBundle)

        }

    }

    /// The "Top Shelf Image" asset catalog image resource.
    static let topShelf = ImageResource(name: "Top Shelf Image", bundle: resourceBundle)

    /// The "Top Shelf Image Wide" asset catalog image resource.
    static let topShelfImageWide = ImageResource(name: "Top Shelf Image Wide", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "AccentColor" asset catalog color.
    static var accent: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .accent)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "AccentColor" asset catalog color.
    static var accent: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .accent)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "AccentColor" asset catalog color.
    static var accent: SwiftUI.Color { .init(.accent) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "App Icon" asset catalog resource namespace.
    enum AppIcon {

        /// The "App Icon/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon/Front/Content" asset catalog image.
            static var content: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
                .init(resource: .AppIcon.Front.content)
#else
                .init()
#endif
            }

        }

        /// The "App Icon/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon/Back/Content" asset catalog image.
            static var content: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
                .init(resource: .AppIcon.Back.content)
#else
                .init()
#endif
            }

        }

        /// The "App Icon/Middle" asset catalog resource namespace.
        enum Middle {

            /// The "App Icon/Middle/Content" asset catalog image.
            static var content: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
                .init(resource: .AppIcon.Middle.content)
#else
                .init()
#endif
            }

        }

    }

    /// The "App Icon - App Store" asset catalog resource namespace.
    enum AppIconAppStore {

        /// The "App Icon - App Store/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon - App Store/Front/Content" asset catalog image.
            static var content: AppKit.NSImage? {
#if !targetEnvironment(macCatalyst)
                .init(thinnableResource: .AppIconAppStore.Front.content)
#else
                .init()
#endif
            }

        }

        /// The "App Icon - App Store/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon - App Store/Back/Content" asset catalog image.
            static var content: AppKit.NSImage? {
#if !targetEnvironment(macCatalyst)
                .init(thinnableResource: .AppIconAppStore.Back.content)
#else
                .init()
#endif
            }

        }

    }

    /// The "Top Shelf Image" asset catalog image.
    static var topShelf: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .topShelf)
#else
        .init()
#endif
    }

    /// The "Top Shelf Image Wide" asset catalog image.
    static var topShelfImageWide: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .topShelfImageWide)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "App Icon" asset catalog resource namespace.
    enum AppIcon {

        /// The "App Icon/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon/Front/Content" asset catalog image.
            static var content: UIKit.UIImage {
#if !os(watchOS)
                .init(resource: .AppIcon.Front.content)
#else
                .init()
#endif
            }

        }

        /// The "App Icon/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon/Back/Content" asset catalog image.
            static var content: UIKit.UIImage {
#if !os(watchOS)
                .init(resource: .AppIcon.Back.content)
#else
                .init()
#endif
            }

        }

        /// The "App Icon/Middle" asset catalog resource namespace.
        enum Middle {

            /// The "App Icon/Middle/Content" asset catalog image.
            static var content: UIKit.UIImage {
#if !os(watchOS)
                .init(resource: .AppIcon.Middle.content)
#else
                .init()
#endif
            }

        }

    }

    /// The "App Icon - App Store" asset catalog resource namespace.
    enum AppIconAppStore {

        /// The "App Icon - App Store/Front" asset catalog resource namespace.
        enum Front {

            /// The "App Icon - App Store/Front/Content" asset catalog image.
            static var content: UIKit.UIImage? {
#if !os(watchOS)
                .init(thinnableResource: .AppIconAppStore.Front.content)
#else
                .init()
#endif
            }

        }

        /// The "App Icon - App Store/Back" asset catalog resource namespace.
        enum Back {

            /// The "App Icon - App Store/Back/Content" asset catalog image.
            static var content: UIKit.UIImage? {
#if !os(watchOS)
                .init(thinnableResource: .AppIconAppStore.Back.content)
#else
                .init()
#endif
            }

        }

    }

    /// The "Top Shelf Image" asset catalog image.
    static var topShelf: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .topShelf)
#else
        .init()
#endif
    }

    /// The "Top Shelf Image Wide" asset catalog image.
    static var topShelfImageWide: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .topShelfImageWide)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
@available(watchOS, unavailable)
extension ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
@available(watchOS, unavailable)
extension ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif