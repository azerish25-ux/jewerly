//
//  CADEngineSession.swift
//  JewelcraftKit
//
//  The CAD engine's contract, and the events it pushes back to the client.
//
//  The single most important property recovered from the original is that the
//  client never computes geometry. All of it lived in a separate long-lived CAD
//  process, reached over a duplex channel, with an explicit callback channel
//  (`UpdateStudioUICallbackChannel`) pushing state back to the UI. The rebuilt
//  engine is in-process, because an iPad cannot host a Rhino service and a
//  purely local product should not require a network round trip to redraw a
//  ring — but the *seam* is preserved exactly.
//
//  Everything here is therefore `async`, even though the in-process
//  implementation completes without suspension. A remote implementation must be
//  a drop-in replacement, and retrofitting asynchrony onto a synchronous
//  protocol later would touch every call site.
//
//  Rendering is deliberately not part of the engine. The engine *requests* a
//  render and the client fulfils it, which is the same split the original had
//  (Rhino asked V-Ray to render) and the one that keeps a headless or
//  server-side renderer possible later without changing the engine.
//

import Foundation

// MARK: - Identity

public struct SessionID: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct SceneGraphID: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Viewport

/// The viewport state, matching the recovered viewport operations one for one.
public struct ViewportState: Codable, Hashable, Sendable {
    public var target: Vector3
    public var cameraLocation: Vector3
    public var backgroundHex: String
    public var highlightHex: String
    public var showsControls: Bool
    public var fieldOfViewDegrees: Double
    public var ambientIntensity: Double

    public init(
        target: Vector3,
        cameraLocation: Vector3,
        backgroundHex: String = "#101014",
        highlightHex: String = "#F2C14E",
        showsControls: Bool = true,
        fieldOfViewDegrees: Double = 35,
        ambientIntensity: Double = 1
    ) {
        self.target = target
        self.cameraLocation = cameraLocation
        self.backgroundHex = backgroundHex
        self.highlightHex = highlightHex
        self.showsControls = showsControls
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.ambientIntensity = ambientIntensity
    }

    /// A three-quarter view framed on a ring of the given size.
    public static func standard(innerDiameterMillimetres: Double = 17.3, extended: Bool = false) -> ViewportState {
        let radius = Swift.max(4, innerDiameterMillimetres / 2)
        let distance = radius * (extended ? 5.2 : 4.2)
        return ViewportState(
            target: Vector3(radius * 0.35, 0, 0),
            cameraLocation: Vector3(radius * 0.9, distance * 0.55, distance * 0.85)
        )
    }
}

// MARK: - Render requests

/// A request for pixels.
///
/// The engine emits these; the client fulfils them. The `key` is deterministic
/// for the same design, target and revision, so a renderer can cache tiles and
/// so a test can assert that nothing was re-rendered unnecessarily.
public struct RenderRequest: Equatable, Hashable, Sendable {
    public var id: String
    public var target: RenderTarget
    public var designID: DesignID
    /// Bumped on every geometry-affecting change.
    public var revision: Int
    public var viewport: ViewportState
    public var pixelSize: PixelSize

    public init(
        id: String,
        target: RenderTarget,
        designID: DesignID,
        revision: Int,
        viewport: ViewportState,
        pixelSize: PixelSize
    ) {
        self.id = id
        self.target = target
        self.designID = designID
        self.revision = revision
        self.viewport = viewport
        self.pixelSize = pixelSize
    }

    public var key: String {
        "\(designID.rawValue)|\(target.rawValue)|\(revision)|\(pixelSize.width)x\(pixelSize.height)"
    }
}

/// A reference to rendered pixels.
public struct ImageRef: Hashable, Sendable {
    public var key: String
    public var pixelSize: PixelSize
    /// Where the pixels live, so a cache entry and a file on disk are the same
    /// kind of thing to the caller.
    public var location: Location

    public enum Location: Hashable, Sendable {
        case memoryCache
        case file(path: String)
        case remote(url: String)
    }

    public init(key: String, pixelSize: PixelSize, location: Location) {
        self.key = key
        self.pixelSize = pixelSize
        self.location = location
    }
}

// MARK: - Snapshot

/// A flat, cheap description of the current state, for the UI to render without
/// walking the whole model.
public struct ConfigurationSnapshot: Equatable, Sendable {
    public var designID: DesignID
    public var designName: String
    public var spinNumber: SpinNumber
    public var metal1ID: String
    public var metal2ID: String?
    public var centreGemSlotIndex: Int?
    public var gemCount: Int
    public var centreCarat: Double?
    public var centreGirdleWidthMillimetres: Double?
    public var fingerSizeText: String
    public var fingerSizeUS: Double
    public var innerDiameterMillimetres: Double
    public var quarterCaratRounding: Bool
    public var headStyle: HeadStyle
    public var accentPatternKind: AccentPatternKind
    public var freehandEnabled: Bool
    public var partCount: Int
    public var triangleCount: Int
    public var metalGrams: Double
    public var metalVolumeCubicMillimetres: Double
    public var issues: [String]

    public init(
        designID: DesignID,
        designName: String,
        spinNumber: SpinNumber,
        metal1ID: String,
        metal2ID: String? = nil,
        centreGemSlotIndex: Int? = nil,
        gemCount: Int,
        centreCarat: Double? = nil,
        centreGirdleWidthMillimetres: Double? = nil,
        fingerSizeText: String,
        fingerSizeUS: Double,
        innerDiameterMillimetres: Double,
        quarterCaratRounding: Bool,
        headStyle: HeadStyle,
        accentPatternKind: AccentPatternKind,
        freehandEnabled: Bool,
        partCount: Int,
        triangleCount: Int,
        metalGrams: Double,
        metalVolumeCubicMillimetres: Double,
        issues: [String]
    ) {
        self.designID = designID
        self.designName = designName
        self.spinNumber = spinNumber
        self.metal1ID = metal1ID
        self.metal2ID = metal2ID
        self.centreGemSlotIndex = centreGemSlotIndex
        self.gemCount = gemCount
        self.centreCarat = centreCarat
        self.centreGirdleWidthMillimetres = centreGirdleWidthMillimetres
        self.fingerSizeText = fingerSizeText
        self.fingerSizeUS = fingerSizeUS
        self.innerDiameterMillimetres = innerDiameterMillimetres
        self.quarterCaratRounding = quarterCaratRounding
        self.headStyle = headStyle
        self.accentPatternKind = accentPatternKind
        self.freehandEnabled = freehandEnabled
        self.partCount = partCount
        self.triangleCount = triangleCount
        self.metalGrams = metalGrams
        self.metalVolumeCubicMillimetres = metalVolumeCubicMillimetres
        self.issues = issues
    }

    /// One line a UI can show under the model.
    public var summaryLine: String {
        var parts: [String] = [designName, "size \(fingerSizeText)"]
        if let centreCarat {
            parts.append(String(format: "centre %.2f ct", centreCarat))
        }
        parts.append("\(gemCount) stone\(gemCount == 1 ? "" : "s")")
        parts.append(String(format: "%.2f g", metalGrams))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Events

/// What the engine pushes back to the client.
public enum EngineEvent: Equatable, Sendable {
    case sessionOpened(session: SessionID)
    case sessionClosed(session: SessionID)
    case designLoaded(session: SessionID, graph: SceneGraphID, partCount: Int, gemCount: Int)
    case configurationChanged(session: SessionID, snapshot: ConfigurationSnapshot, revision: Int)
    case gemReportUpdated(session: SessionID, lines: [GemReportLine])
    case selectionChanged(session: SessionID, itemIDs: [GraphItemID], gemSlotIndices: [Int])
    case undoStateChanged(session: SessionID, canUndo: Bool, canRedo: Bool, depth: Int)
    case freehandChanged(session: SessionID, state: FreehandState)
    case renderRequested(session: SessionID, request: RenderRequest)
    case failed(session: SessionID, message: String)

    public var session: SessionID {
        switch self {
        case .sessionOpened(let session), .sessionClosed(let session),
             .designLoaded(let session, _, _, _),
             .configurationChanged(let session, _, _),
             .gemReportUpdated(let session, _),
             .selectionChanged(let session, _, _),
             .undoStateChanged(let session, _, _, _),
             .freehandChanged(let session, _),
             .renderRequested(let session, _),
             .failed(let session, _):
            return session
        }
    }
}

public protocol EngineEventListener: AnyObject {
    func engineDidEmit(_ event: EngineEvent)
}

/// Bridges the listener protocol to an `AsyncStream`, for callers that would
/// rather await events than implement a delegate.
public final class EngineEventStream: EngineEventListener, @unchecked Sendable {

    public typealias Continuation = AsyncStream<EngineEvent>.Continuation

    private let lock = NSLock()
    private var continuation: Continuation?
    public let stream: AsyncStream<EngineEvent>

    public init(bufferingPolicy: AsyncStream<EngineEvent>.Continuation.BufferingPolicy = .bufferingNewest(128)) {
        // `AsyncStream.makeStream` would be tidier but is newer than this
        // package's macOS floor, so the continuation is captured synchronously
        // from the initialiser's closure instead.
        var captured: Continuation?
        self.stream = AsyncStream<EngineEvent>(bufferingPolicy: bufferingPolicy) { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    public func engineDidEmit(_ event: EngineEvent) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(event)
    }

    public func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }

    /// Collects events until `predicate` is satisfied, or the count limit is
    /// reached. Intended for tests, where turning a stream into an assertion is
    /// the whole point.
    public func collect(
        maximum: Int,
        timeoutSeconds: Double = 2,
        until predicate: @escaping (EngineEvent) -> Bool = { _ in false }
    ) async -> [EngineEvent] {
        var collected: [EngineEvent] = []
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        for await event in stream {
            collected.append(event)
            if predicate(event) || collected.count >= maximum { break }
            if Date() > deadline { break }
        }
        return collected
    }
}

// MARK: - Errors

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case sessionClosed
    case noDesignLoaded
    case unknownDesign(String)
    case unknownGemSlot(Int)
    case invalidConfiguration([String])
    case metalPairUnsupported(String, String)
    case caratOutOfRange(requested: Double, allowed: ClosedRange<Double>)
    case unknownPart(String)
    case renderingUnavailable

    public var description: String {
        switch self {
        case .sessionClosed:
            return "The engine session is closed."
        case .noDesignLoaded:
            return "No design is loaded in this session."
        case .unknownDesign(let id):
            return "No design with id \(id) exists in the catalogue."
        case .unknownGemSlot(let slot):
            return "Stone slot \(slot) does not exist in the loaded design."
        case .invalidConfiguration(let issues):
            return "The configuration is not saleable: \(issues.joined(separator: "; "))."
        case .metalPairUnsupported(let first, let second):
            return "\(first) cannot be paired with \(second) on a single ring."
        case .caratOutOfRange(let requested, let allowed):
            return String(
                format: "A centre stone of %.2f ct is outside the %.2f–%.2f ct this design supports.",
                requested, allowed.lowerBound, allowed.upperBound
            )
        case .unknownPart(let id):
            return "No part with id \(id) exists in the current model."
        case .renderingUnavailable:
            return "No renderer is attached to fulfil this request."
        }
    }
}

// MARK: - The session

/// A long-lived engine session bound to one design and configuration.
///
/// Operation names deliberately track the recovered contract's groups — gems,
/// freehand, viewport, graph, undo, materials — rather than being invented
/// afresh, so that the fidelity ledger can be read against the reverse
/// engineering report line by line.
public protocol CADEngineSession: AnyObject {

    var id: SessionID { get }
    var isOpen: Bool { get }
    /// Bumped on every change that affects geometry or appearance.
    var revision: Int { get }

    // Listeners

    func addListener(_ listener: EngineEventListener)
    func removeListener(_ listener: EngineEventListener)

    // Lifecycle

    /// Opens the session on a design and its starting configuration.
    @discardableResult
    func open(design: DesignDetail, configuration: Configuration) async throws -> SceneGraphID
    func close() async

    /// Loads a different design, keeping the session alive.
    @discardableResult
    func loadDesign(_ designID: DesignID) async throws -> SceneGraphID

    // Configuration

    func setMetals(metal1: Metal, metal2: Metal?) async throws
    func setGems(_ gems: [GemSelection]) async throws
    func setCentreGem(carat: Double, shape: GemShape?, colourID: String?, qualityID: String?) async throws
    func setFingerSize(_ fingerSize: FingerSize) async throws

    // The head style and the accent pattern belong to the *design*, not to the
    // configuration: the recovered command-line contract carried gems, metals,
    // finger size and iteration identity but no setting argument, because a
    // setting was chosen when the design was, through the gem-setting facet.
    // A configurator that let the setting float would be inventing scope.

    /// Flips quarter-carat rounding and returns the new state.
    @discardableResult
    func toggleQuarterCaratRounding() async throws -> Bool

    /// Stones whose size the customer set by hand.
    func manualSizedStones() async -> [GemReportLine]

    /// Sizes one stone by hand, bypassing the design's suggestion.
    func setManualSize(slotIndex: Int, carat: Double) async throws

    // Freehand

    func setFreehand(_ state: FreehandState) async throws
    @discardableResult
    func toggleFreehandCommonCentreMode() async throws -> Bool
    /// Flips every freehand component's visibility.
    func toggleFreehandVisibility() async throws
    func setFreehandVisibility(_ isVisible: Bool, partNamed name: String) async throws
    func setViewportHandleDrawScale(_ scale: Double) async throws
    func updateCurve(partID: String, controlPoints: [Vector2]) async throws
    func updateValueChooser(_ value: Double) async throws

    // Highlighting

    func highlight(items: [GraphItemID]) async
    func highlightGem(slotIndex: Int) async
    func highlightAccentGems(_ enabled: Bool) async
    func clearHighlights() async

    // History

    func undo() async throws
    func redo() async throws

    // State

    func configuration() async -> Configuration?
    func snapshot() async -> ConfigurationSnapshot?
    func sceneGraph() async -> SceneGraph?
    func gemReport() async -> [GemReportLine]
    /// Builds the current model, returning the parts the renderer needs.
    func build() async throws -> BuiltRing

    // Viewport and rendering

    func setViewport(_ viewport: ViewportState) async
    func viewport() async -> ViewportState
    /// Asks for pixels at a target size. The client fulfils the request; the
    /// engine does not own a renderer.
    @discardableResult
    func requestRender(target: RenderTarget) async throws -> RenderRequest
}
