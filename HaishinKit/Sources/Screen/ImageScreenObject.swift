import CoreImage

private enum ImageSourceError: Error {
    case unsupported
    case invalidDataURL
    case invalidBase64
    case imageDecodingFailed
}

private protocol ImageSource {
    /// The original URL of the image source.
    var url: URL { get }

    /// Converts the image source into a CIImage.
    func toImage() throws -> CIImage
}

private enum ImageSourceFactory {
    static func parse(_ url: URL?) throws -> any ImageSource {
        guard let url else {
            throw ImageSourceError.unsupported
        }

        switch url.scheme {
        case "data":
            return DataImageSource(url: url)
        default:
            throw ImageSourceError.unsupported
        }
    }
}

private struct DataImageSource: ImageSource {
    let url: URL

    func toImage() throws -> CIImage {
        // data:[<mediatype>][;base64],<data>
        let urlString = url.absoluteString
        guard let base64Range = urlString.range(of: "base64,") else {
            throw ImageSourceError.invalidDataURL
        }
        let base64String = String(urlString[base64Range.upperBound...])
        guard let data = Data(base64Encoded: base64String) else {
            throw ImageSourceError.invalidBase64
        }
        guard let image = CIImage(data: data) else {
            throw ImageSourceError.imageDecodingFailed
        }
        return image
    }
}

/// An object that manages offscreen rendering a cgImage source.
public final class ImageScreenObject: ScreenObject {
    public static let type = "image"

    private enum Keys {
        static let source = "source"
    }

    /// Specifies the image.
    public var ciImage: CIImage? {
        didSet {
            guard ciImage != oldValue else {
                return
            }
            invalidateLayout()
        }
    }

    override public var elements: [String: String] {
        get {
            return [
                Keys.source: source ?? ""
            ]
        }
        set {
            do {
                try setSource(newValue[Keys.source])
            } catch {
                logger.warn(error)
            }
        }
    }

    private var source: String?

    override public func makeImage(_ renderer: some ScreenRenderer) -> CIImage? {
        guard let ciImage, ciImage.extent.width > 0, ciImage.extent.height > 0 else {
            return nil
        }
        // Scale the source image to the object's layout size and let the renderer composite it.
        // Any part that extends beyond the canvas is clipped naturally when the final CIImage is
        // rendered into the (canvas-sized) pixel buffer — there is no need to special-case the
        // "drawing area exceeded" path. The previous implementation tried to crop/reposition the
        // image for right/center/bottom-aligned objects and produced an empty (invisible) image
        // whenever the bounds touched a canvas edge, which is exactly the case for corner logos.
        //
        // A zero `size` component means "use the image's natural extent" (see makeBounds), so we
        // fall back to a scale of 1 for that axis instead of dividing by it (which would yield 0).
        let scaleX = size.width == 0 ? 1 : size.width / ciImage.extent.width
        let scaleY = size.height == 0 ? 1 : size.height / ciImage.extent.height
        return ciImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
    }

    override public func makeBounds(_ size: CGSize) -> CGRect {
        guard let ciImage else {
            return super.makeBounds(size)
        }
        return super.makeBounds(size == .zero ? ciImage.extent.size : size)
    }

    func setSource(_ source: String?) throws {
        self.source = source
        let imageSource = try ImageSourceFactory.parse(URL(string: source ?? ""))
        ciImage = try imageSource.toImage()
    }
}
