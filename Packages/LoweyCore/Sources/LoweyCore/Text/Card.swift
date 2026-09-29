import Foundation

/// A picture or a video standing in the world as a thin card (a photo on a stand, a screen on the set), instead of
/// being pasted over the frame. It is a real object: it catches the light at its edges, the camera can walk around it,
/// characters can stand in front of it. Base-centred like everything else: one metre tall at scale 1, `aspect` wide.
public struct CardRecipe: Codable, Hashable, Sendable {
    /// A picture inside the project's `assets/` folder.
    public var image: String?
    /// A video inside the project's `assets/` folder (plays on the card).
    public var video: String?
    /// Timeline time (s) of the video's first frame. Before it, the card shows that first frame.
    public var videoStart: Double?
    /// The video's length (s). After it ends it holds its last frame, or loops.
    public var videoDuration: Double?
    public var videoLoop: Bool?
    /// Width ÷ height of the picture.
    public var aspect: Double
    /// Card thickness (metres) and the border around the picture (a fraction of the height).
    public var thickness: Double
    public var border: Double

    public init(image: String? = nil, video: String? = nil, videoStart: Double? = nil, videoDuration: Double? = nil, videoLoop: Bool? = nil,
                aspect: Double = 16.0 / 9, thickness: Double = 0.02, border: Double = 0.03) {
        self.image = image
        self.video = video
        self.videoStart = videoStart
        self.videoDuration = videoDuration
        self.videoLoop = videoLoop
        self.aspect = aspect
        self.thickness = thickness
        self.border = border
    }

    /// Picture size in metres at scale 1 (height 1).
    public var pictureSize: (width: Double, height: Double) {
        (max(aspect, 0.05), 1)
    }

    /// Outer size of the card, border included.
    public var cardSize: (width: Double, height: Double, depth: Double) {
        let picture = pictureSize
        return (picture.width + 2 * border, picture.height + 2 * border, max(thickness, 0.002))
    }

    /// What the card shows at timeline `time`: the picture's file name, or a `VideoFrameKey` (frame-exact, 60 fps steps).
    /// Before the video starts the card holds its first frame; nil when it has nothing to show.
    public func frameKey(at time: Double) -> String? {
        if let video {
            let local = max(time - (videoStart ?? 0), 0)
            let step = 1.0 / 60
            var wrapped = local
            if let duration = videoDuration, duration > step {
                wrapped = videoLoop == true ? local.truncatingRemainder(dividingBy: duration) : min(local, duration - step)
            }
            return VideoFrameKey.make(file: video, time: (max(wrapped, 0) / step).rounded(.down) * step)
        }
        return image
    }

    /// Native bounds (base-centred, facing +Z).
    public var bounds: Bounds {
        let size = cardSize
        return Bounds(min: Vec3(-size.width / 2, 0, -size.depth / 2), max: Vec3(size.width / 2, size.height, size.depth / 2))
    }
}
