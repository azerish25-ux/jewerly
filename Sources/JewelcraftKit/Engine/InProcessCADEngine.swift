//
//  InProcessCADEngine.swift
//  JewelcraftKit
//
//  The engine, implemented in process.
//
//  Every mutation goes through one place — `mutate` — which validates, records
//  the new configuration in the undo history, rebuilds the model, and emits the
//  events the client is listening for. A single path means the graph, the
//  geometry, the gem report, the snapshot and the undo stack can never disagree
//  about what the ring currently is, which is the bug class that makes a
//  configurator feel unreliable even when each part works on its own.
//
//  Rebuilds are full rather than incremental. A ring is a few thousand triangles
//  and the builder is pure, so a full rebuild is fast, obviously correct, and
//  has no invalidation logic to get wrong. Incremental reconstruction is a later
//  optimisation with a measurement behind it, not a guess made now.
//

import Foundation

public final class InProcessCADEngine: CADEngineSession {

    private final class WeakListener {
        weak var value: EngineEventListener?
        init(_ value: EngineEventListener) {
            self.value = value
        }
    }

    // MARK: - Identity and dependencies

    public let id: SessionID
    private let catalog: CatalogService
    private let sizer: GemSizer

    // MARK: - State

    private var listeners: [WeakListener] = []
    private var isOpenFlag = false
    private var design: DesignDetail?
    private var configurationValue: Configuration?
    private var history: UndoStack<Configuration>?
    private var graphValue = SceneGraph(root: GraphItem(id: GraphItemID("model"), name: "Model", kind: .root))
    private var graphIDValue: SceneGraphID?
    private var builtValue: BuiltRing?
    private var viewportValue = ViewportState.standard()
    private var revisionValue = 0

    public init(
        sessionID: SessionID,
        catalog: CatalogService,
        sizer: GemSizer = GemSizer()
    ) {
        self.id = sessionID
        self.catalog = catalog
        self.sizer = sizer
    }

    /// A session with an id derived from the design and an iteration counter, so
    /// two sessions on the same design are distinguishable and reproducible in
    /// tests.
    public convenience init(
        catalog: CatalogService,
        designID: DesignID,
        iterationIndex: Int = 0,
        sizer: GemSizer = GemSizer()
    ) {
        self.init(
            sessionID: SessionID("\(designID.rawValue)-\(iterationIndex)"),
            catalog: catalog,
            sizer: sizer
        )
    }

    // MARK: - Protocol conformance: identity

    public var isOpen: Bool { isOpenFlag }

    public var revision: Int { revisionValue }

    // MARK: - Listeners

    public func addListener(_ listener: EngineEventListener) {
        listeners.removeAll { $0.value == nil }
        listeners.append(WeakListener(listener))
    }

    public func removeListener(_ listener: EngineEventListener) {
        listeners.removeAll { $0.value == nil || $0.value === listener }
    }

    private func emit(_ event: EngineEvent) {
        for listener in listeners {
            listener.value?.engineDidEmit(event)
        }
    }

    // MARK: - Lifecycle

    @discardableResult
    public func open(design: DesignDetail, configuration: Configuration) async throws -> SceneGraphID {
        let issues = configuration.validationIssues
        if !issues.isEmpty {
            emit(.failed(session: id, message: EngineError.invalidConfiguration(issues).description))
            throw EngineError.invalidConfiguration(issues)
        }

        self.design = design
        self.configurationValue = configuration
        self.history = UndoStack(initial: configuration)
        self.isOpenFlag = true
        self.viewportValue = .standard(
            innerDiameterMillimetres: configuration.fingerSize.innerDiameterMillimetres
        )

        emit(.sessionOpened(session: id))
        try rebuild()
        return graphIDValue ?? SceneGraphID("graph.\(design.id.rawValue)")
    }

    public func close() async {
        guard isOpenFlag else { return }
        isOpenFlag = false
        builtValue = nil
        emit(.sessionClosed(session: id))
        listeners.removeAll()
    }

    @discardableResult
    public func loadDesign(_ designID: DesignID) async throws -> SceneGraphID {
        guard let next = catalog.design(id: designID) else {
            throw EngineError.unknownDesign(designID.rawValue)
        }
        let configuration = try ConfigurationFactory.makeConfiguration(for: next, catalog: catalog)
        return try await open(design: next, configuration: configuration)
    }

    // MARK: - Configuration

    public func setMetals(metal1: Metal, metal2: Metal?) async throws {
        if let metal2, !metal1.canPair(with: metal2) {
            throw EngineError.metalPairUnsupported(metal1.displayName, metal2.displayName)
        }
        try mutate { configuration in
            configuration.metal1 = metal1
            configuration.metal2 = metal2
        }
    }

    public func setGems(_ gems: [GemSelection]) async throws {
        try mutate { configuration in
            configuration.gems = gems
        }
    }

    public func setCentreGem(
        carat: Double,
        shape: GemShape?,
        colourID: String?,
        qualityID: String?
    ) async throws {
        guard let design else { throw EngineError.noDesignLoaded }
        let range = design.summary.centreGemCaratRange
        guard range.contains(carat) else {
            throw EngineError.caratOutOfRange(requested: carat, allowed: range)
        }

        try mutate { configuration in
            guard let index = configuration.gems.firstIndex(where: { $0.role == .centre })
                ?? configuration.gems.indices.first else {
                throw EngineError.unknownGemSlot(0)
            }
            configuration.gems[index].carat = CaratRounding.rounded(
                carat,
                enabled: configuration.quarterCaratRounding
            )
            configuration.gems[index].manualSize = true
            if let shape { configuration.gems[index].shape = shape }
            if let colourID { configuration.gems[index].colourID = colourID }
            if let qualityID { configuration.gems[index].qualityID = qualityID }
        }
    }

    public func setFingerSize(_ fingerSize: FingerSize) async throws {
        let quantised = fingerSize.quantised()
        guard quantised.isWithinOfferedRange else {
            throw EngineError.invalidConfiguration([
                "Ring size \(quantised.displayText) is outside the offered range."
            ])
        }
        try mutate { configuration in
            configuration.fingerSize = quantised
        }
        // Reframe the camera for the new ring size. The size change itself is
        // already recorded by `mutate`, so nothing extra goes in the history.
        viewportValue = .standard(innerDiameterMillimetres: quantised.innerDiameterMillimetres)
    }

    @discardableResult
    public func toggleQuarterCaratRounding() async throws -> Bool {
        try mutate { configuration in
            configuration.quarterCaratRounding.toggle()
            configuration.applyCaratRounding()
        }
        return configurationValue?.quarterCaratRounding ?? false
    }

    public func manualSizedStones() async -> [GemReportLine] {
        (builtValue?.gemReportLines ?? []).filter { $0.isManualSize }
    }

    public func setManualSize(slotIndex: Int, carat: Double) async throws {
        try mutate { configuration in
            guard let index = configuration.gems.firstIndex(where: { $0.slotIndex == slotIndex }) else {
                throw EngineError.unknownGemSlot(slotIndex)
            }
            configuration.gems[index].carat = Swift.max(0.001, carat)
            configuration.gems[index].manualSize = true
        }
    }

    // MARK: - Freehand

    public func setFreehand(_ state: FreehandState) async throws {
        try mutate { configuration in
            configuration.freehand = state
        }
        emit(.freehandChanged(session: id, state: configurationValue?.freehand ?? .disabled))
    }

    @discardableResult
    public func toggleFreehandCommonCentreMode() async throws -> Bool {
        try mutate { configuration in
            configuration.freehand.commonCentreMode.toggle()
        }
        let state = configurationValue?.freehand ?? .disabled
        emit(.freehandChanged(session: id, state: state))
        return state.commonCentreMode
    }

    public func toggleFreehandVisibility() async throws {
        try mutate { configuration in
            // Flipping visibility applies to every component at once, which is
            // what "toggle visibility" means when several parts are editable.
            let anyVisible = configuration.freehand.parts.contains { $0.isVisible }
            for index in configuration.freehand.parts.indices {
                configuration.freehand.parts[index].isVisible = !anyVisible
            }
        }
        emit(.freehandChanged(session: id, state: configurationValue?.freehand ?? .disabled))
    }

    public func setFreehandVisibility(_ isVisible: Bool, partNamed name: String) async throws {
        try mutate { configuration in
            configuration.freehand.setVisibility(isVisible, ofPartNamed: name)
        }
        emit(.freehandChanged(session: id, state: configurationValue?.freehand ?? .disabled))
    }

    public func setViewportHandleDrawScale(_ scale: Double) async throws {
        try mutate { configuration in
            configuration.freehand.handleDrawScale = Swift.max(0.1, Swift.min(4, scale))
        }
        emit(.freehandChanged(session: id, state: configurationValue?.freehand ?? .disabled))
    }

    public func updateCurve(partID: String, controlPoints: [Vector2]) async throws {
        guard let configuration = configurationValue,
              configuration.freehand.parts.contains(where: { $0.id == partID }) else {
            throw EngineError.unknownPart(partID)
        }
        try mutate { updated in
            guard let index = updated.freehand.parts.firstIndex(where: { $0.id == partID }) else { return }
            updated.freehand.parts[index].controlPoints = controlPoints
        }
    }

    public func updateValueChooser(_ value: Double) async throws {
        try mutate { configuration in
            configuration.freehand.valueChooserValue = value
        }
        emit(.freehandChanged(session: id, state: configurationValue?.freehand ?? .disabled))
    }

    // MARK: - Highlighting

    public func highlight(items itemIDs: [GraphItemID]) async {
        guard let configuration = configurationValue else { return }
        graphValue.clearHighlights()
        var slots: [Int] = []
        for itemID in itemIDs {
            graphValue.highlight(itemID)
            if let item = graphValue.item(id: itemID), let slotIndex = item.gemSlotIndex {
                slots.append(slotIndex)
            }
        }
        var updated = configuration
        updated.highlightedGemSlots = Set(slots)
        configurationValue = updated
        emit(.selectionChanged(
            session: id,
            itemIDs: graphValue.highlightedItems.map(\.id),
            gemSlotIndices: slots.sorted()
        ))
    }

    public func highlightGem(slotIndex: Int) async {
        guard let configuration = configurationValue else { return }
        graphValue.clearHighlights()
        graphValue.highlightGemSlot(slotIndex)
        var updated = configuration
        updated.highlightedGemSlots = [slotIndex]
        configurationValue = updated
        emit(.selectionChanged(
            session: id,
            itemIDs: graphValue.highlightedItems.map(\.id),
            gemSlotIndices: [slotIndex]
        ))
    }

    public func highlightAccentGems(_ enabled: Bool) async {
        guard let configuration = configurationValue else { return }
        let accentSlots = Set(configuration.accentGems.map(\.slotIndex))
        graphValue.clearHighlights()
        for item in graphValue.items where item.kind == .gem {
            if let slot = item.gemSlotIndex, accentSlots.contains(slot) {
                graphValue.highlight(item.id, enabled: enabled)
            }
        }
        var updated = configuration
        updated.highlightedGemSlots = enabled ? accentSlots : []
        configurationValue = updated
        emit(.selectionChanged(
            session: id,
            itemIDs: graphValue.highlightedItems.map(\.id),
            gemSlotIndices: Array(updated.highlightedGemSlots).sorted()
        ))
    }

    public func clearHighlights() async {
        guard configurationValue != nil else { return }
        graphValue.clearHighlights()
        configurationValue?.clearHighlights()
        emit(.selectionChanged(session: id, itemIDs: [], gemSlotIndices: []))
    }

    // MARK: - History

    public func undo() async throws {
        guard isOpenFlag else { throw EngineError.sessionClosed }
        guard var history, let state = history.undo() else {
            emitUndoState()
            return
        }
        self.history = history
        configurationValue = state
        try rebuild()
    }

    public func redo() async throws {
        guard isOpenFlag else { throw EngineError.sessionClosed }
        guard var history, let state = history.redo() else {
            emitUndoState()
            return
        }
        self.history = history
        configurationValue = state
        try rebuild()
    }

    // MARK: - State

    public func configuration() async -> Configuration? {
        configurationValue
    }

    public func sceneGraph() async -> SceneGraph? {
        graphValue
    }

    public func gemReport() async -> [GemReportLine] {
        builtValue?.gemReportLines ?? []
    }

    public func snapshot() async -> ConfigurationSnapshot? {
        guard let design, let configuration = configurationValue, let built = builtValue else {
            return nil
        }
        return ConfigurationSnapshotFactory.make(
            design: design,
            configuration: configuration,
            built: built
        )
    }

    public func build() async throws -> BuiltRing {
        guard let builtValue else { throw EngineError.noDesignLoaded }
        return builtValue
    }

    // MARK: - Viewport and rendering

    public func setViewport(_ viewport: ViewportState) async {
        viewportValue = viewport
        markViewportChanged()
    }

    public func viewport() async -> ViewportState {
        viewportValue
    }

    @discardableResult
    public func requestRender(target: RenderTarget) async throws -> RenderRequest {
        guard let design else { throw EngineError.noDesignLoaded }
        let request = RenderRequest(
            id: "render.\(id.rawValue).\(revisionValue).\(target.rawValue)",
            target: target,
            designID: design.id,
            revision: revisionValue,
            viewport: viewportValue,
            pixelSize: target.pixelSize
        )
        emit(.renderRequested(session: id, request: request))
        return request
    }

    /// A camera move changes what must be redrawn but not what is modelled, so
    /// it advances the revision — invalidating cached renders — without pushing
    /// an undo entry or rebuilding geometry.
    private func markViewportChanged() {
        revisionValue += 1
    }

    // MARK: - The single mutation path

    /// Validates, records, rebuilds and notifies. Every configuration change
    /// goes through here.
    private func mutate(_ body: (inout Configuration) throws -> Void) throws {
        guard isOpenFlag else { throw EngineError.sessionClosed }
        guard var configuration = configurationValue else { throw EngineError.noDesignLoaded }

        try body(&configuration)

        let issues = configuration.validationIssues
        if !issues.isEmpty {
            emit(.failed(session: id, message: EngineError.invalidConfiguration(issues).description))
            throw EngineError.invalidConfiguration(issues)
        }

        configurationValue = configuration
        history?.record(configuration)
        try rebuild()
    }

    /// Rebuilds geometry, the graph, and everything derived from them, then
    /// emits the resulting state.
    private func rebuild() throws {
        guard let design, let configuration = configurationValue else {
            throw EngineError.noDesignLoaded
        }

        let parameters = Self.parameters(for: design, configuration: configuration)
        let plan = Self.gemPlan(for: design, configuration: configuration)

        let built = RingBuilder.build(
            designID: design.id,
            parameters: parameters,
            plan: plan,
            metal: configuration.metal1,
            metal2: configuration.metal2,
            sizer: sizer
        )

        builtValue = built
        revisionValue += 1
        graphIDValue = SceneGraphID("graph.\(design.id.rawValue).\(configuration.iterationIndex)")
        graphValue = Self.makeGraph(design: design, built: built, revision: revisionValue)

        emit(.designLoaded(
            session: id,
            graph: graphIDValue ?? SceneGraphID("graph"),
            partCount: built.parts.count,
            gemCount: built.gemPlacements.count
        ))
        emit(.configurationChanged(
            session: id,
            snapshot: ConfigurationSnapshotFactory.make(
                design: design,
                configuration: configuration,
                built: built
            ),
            revision: revisionValue
        ))
        emit(.gemReportUpdated(session: id, lines: built.gemReportLines))
        emitUndoState()
    }

    private func emitUndoState() {
        emit(.undoStateChanged(
            session: id,
            canUndo: history?.canUndo ?? false,
            canRedo: history?.canRedo ?? false,
            depth: history?.depth ?? 0
        ))
    }

    // MARK: - Derivation

    /// The design's parameters, resolved against the customer's ring size.
    public static func parameters(for design: DesignDetail, configuration: Configuration) -> RingParameters {
        RingParameters(
            innerDiameterMillimetres: configuration.fingerSize.innerDiameterMillimetres,
            shankWidthMillimetres: design.shankWidthMillimetres,
            shankThicknessMillimetres: design.shankThicknessMillimetres,
            shankProfile: design.shankProfile,
            shoulderTaperMillimetres: design.shoulderTaperMillimetres,
            baseWidthTaperFraction: design.baseWidthTaperFraction,
            head: design.head,
            accentMetalWidthMillimetres: design.accentMetalWidthMillimetres,
            resolution: 96
        )
    }

    /// Turns the configuration's stones into a plan for the builder. The accent
    /// pattern comes from the design rather than being invented here.
    public static func gemPlan(for design: DesignDetail, configuration: Configuration) -> GemPlan {
        let centre = configuration.gems.first { $0.role == .centre }
        let accents = configuration.gems
            .filter { $0.role != .centre }
            .sorted { $0.slotIndex < $1.slotIndex }
        return GemPlan(centre: centre, accents: accents, accentPattern: design.accentPattern)
    }

    /// Builds the addressable graph from the assembled parts.
    static func makeGraph(design: DesignDetail, built: BuiltRing, revision: Int) -> SceneGraph {
        let rootID = GraphItemID("model")
        var graph = SceneGraph(root: GraphItem(
            id: rootID,
            name: "Model",
            kind: .root,
            userData: ["revision": "\(revision)"]
        ))

        let designItemID = GraphItemID("design.\(design.id.rawValue)")
        graph.append(GraphItem(
            id: designItemID,
            name: design.summary.name,
            kind: .design,
            parentID: rootID,
            userData: [
                "spinNumber": design.summary.spinNumber.rawValue,
                "baseRingType": design.summary.baseRingType.rawValue,
                "centreGemGraphIndex": "\(design.centreGemGraphIndex)",
                "centreGemGUID": design.centreGemGUID,
                "blockInstanceGUID": design.centreGemGUID
            ]
        ))

        for part in built.parts {
            var userData = part.userData
            if let slotIndex = part.gemSlotIndex,
               let placement = built.gemPlacements.first(where: { $0.slotIndex == slotIndex }) {
                userData["role"] = placement.role.rawValue
            }
            graph.append(GraphItem(
                id: GraphItemID("item.\(part.id)"),
                name: part.name,
                kind: Self.graphKind(for: part.kind),
                parentID: designItemID,
                userData: userData,
                partGroupID: part.id,
                gemSlotIndex: part.gemSlotIndex,
                isVisible: part.isVisibleByDefault
            ))
        }

        return graph
    }

    private static func graphKind(for partKind: PartKind) -> GraphItemKind {
        switch partKind {
        case .shank: return .shank
        case .railGuide: return .railGuide
        case .prong: return .prong
        case .basket, .bezel, .bead, .channel, .haloRail: return .partGroup
        case .centreStone, .accentStone, .haloStone: return .gem
        }
    }
}

// MARK: - Construction helpers

/// Builds a starting configuration from a design.
///
/// Kept outside the engine so the catalogue, the app and the tests all create a
/// design's first configuration the same way — the original's "packaged design
/// with a suggested centre stone" behaviour.
public enum ConfigurationFactory {

    public static func makeConfiguration(
        for design: DesignDetail,
        catalog: CatalogService,
        fingerSize: FingerSize = .defaultValue,
        metalID: String? = nil,
        iterationIndex: Int = 0
    ) throws -> Configuration {
        let metalCatalog = StandardMetals.catalog
        let metal: Metal
        if let metalID,
           let found = metalCatalog.metal(id: metalID),
           design.summary.metalIDs.contains(metalID) {
            metal = found
        } else if let firstID = design.summary.metalIDs.first,
                  let first = metalCatalog.metal(id: firstID) {
            metal = first
        } else {
            metal = StandardMetals.all[0]
        }

        let gems = design.gemSlots
            .sorted { $0.id < $1.id }
            .map { slot -> GemSelection in
                let carat = slot.role == .centre ? design.suggestedCentreCarat : slot.defaultCarat
                return GemSelection(
                    slotIndex: slot.id,
                    role: slot.role,
                    material: slot.defaultMaterial,
                    shape: slot.defaultShape,
                    colourID: slot.defaultColourID,
                    qualityID: slot.defaultQualityID,
                    carat: carat,
                    manualSize: false,
                    graphicIndex: slot.graphIndex
                )
            }

        var configuration = Configuration(
            id: "\(design.id.rawValue)-iteration-\(iterationIndex)",
            designID: design.id,
            iterationIndex: iterationIndex,
            metal1: metal,
            metal2: nil,
            gems: gems,
            fingerSize: fingerSize,
            quarterCaratRounding: true,
            freehand: .disabled,
            highlightedGemSlots: []
        )
        configuration.applyCaratRounding()
        return configuration
    }
}

/// Builds the flat snapshot from the current state.
enum ConfigurationSnapshotFactory {

    static func make(
        design: DesignDetail,
        configuration: Configuration,
        built: BuiltRing
    ) -> ConfigurationSnapshot {
        let centre = built.gemPlacements.first { $0.role == .centre }
        return ConfigurationSnapshot(
            designID: design.id,
            designName: design.summary.name,
            spinNumber: design.summary.spinNumber,
            metal1ID: configuration.metal1.id,
            metal2ID: configuration.metal2?.id,
            centreGemSlotIndex: configuration.centreGem?.slotIndex,
            gemCount: configuration.gems.count,
            centreCarat: configuration.centreCarat,
            centreGirdleWidthMillimetres: centre?.girdleWidthMillimetres,
            fingerSizeText: configuration.fingerSize.displayText,
            fingerSizeUS: configuration.fingerSize.usSize,
            innerDiameterMillimetres: configuration.fingerSize.innerDiameterMillimetres,
            quarterCaratRounding: configuration.quarterCaratRounding,
            headStyle: design.head.style,
            accentPatternKind: design.accentPattern.kind,
            freehandEnabled: configuration.freehand.isEnabled,
            partCount: built.parts.count,
            triangleCount: built.triangleCount,
            metalGrams: built.metalGrams,
            metalBreakdown: built.metalBreakdown,
            metalVolumeCubicMillimetres: built.metalVolumeCubicMillimetres,
            issues: configuration.validationIssues
        )
    }
}
