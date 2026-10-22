import QuartzCore

/// What the diagnostics overlay (⌥⌘I) shows.
struct PlaybackStats: Equatable {
    var videoFPS: Double = 0
    var drawsPerSecond: Double = 0
    var droppedFrames = 0
    var gpuMilliseconds: Double = 0
    var videoSize = ""
    var drawableSize = ""
}

/// Rolling one-second counters behind PlaybackStats. Main thread only.
struct StatsWindow {
    private var videoFrames: [CFTimeInterval] = []
    private var draws: [CFTimeInterval] = []
    private var gpuAverage: Double = 0
    private var videoSize = ""

    mutating func videoFrame(width: Int, height: Int) {
        let now = CACurrentMediaTime()
        videoFrames = videoFrames.filter { now - $0 < 1 } + [now]
        videoSize = "\(width)×\(height)"
    }

    mutating func draw() {
        let now = CACurrentMediaTime()
        draws = draws.filter { now - $0 < 1 } + [now]
    }

    mutating func gpu(_ milliseconds: Double) {
        gpuAverage = gpuAverage == 0 ? milliseconds : gpuAverage * 0.9 + milliseconds * 0.1
    }

    func snapshot(size: CGSize) -> PlaybackStats {
        let now = CACurrentMediaTime()
        return PlaybackStats(videoFPS: Double(videoFrames.filter { now - $0 < 1 }.count),
                      drawsPerSecond: Double(draws.filter { now - $0 < 1 }.count),
                      droppedFrames: 0, gpuMilliseconds: gpuAverage, videoSize: videoSize,
                      drawableSize: "\(Int(size.width))×\(Int(size.height))")
    }
}
