//
//  StudioModel.swift
//  Jewelcraft
//
//  The app's single source of truth: the catalogue, one engine session, the
//  current quote, and the order register.
//
//  The shape follows the original's seam. Geometry lives behind an engine that
//  *pushes* state, so this object subscribes to it rather than polling; views
//  read published values and call intent methods. No view computes geometry,
//  prices or totals — those come back from the core, which is what the test
//  suite covers.
//

import Foundation
import Observation
import JewelcraftKit

@MainActor
@Observable
final class StudioModel {

    // MARK: - Collaborators

    let catalog: CatalogService
    let gems = GemFixtures.catalog
    let materials = MaterialFixtures.library
    let pricing: PricingEngine
    let orderService: OrderService

    // MARK: - Search

    var searchText: String = "" { didSet { refreshResults() } }
    private(set) var filter = DesignFilter.empty
    private(set) var results: [DesignSummary] = []
    private(set) var facets: [FacetGroup: [FacetDescriptor]] = [:]
    private(set) var scopeTitle = "All designs"

    // MARK: - The open ring

    private(set) var design: DesignDetail?
    private(set) var snapshot: ConfigurationSnapshot?
    private(set) var gemReport: [GemReportLine] = []
    private(set) var built: BuiltRing?
    private(set) var quote: Quote?
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var isBusy = false
    var errorMessage: String?

    private var engine: InProcessCADEngine?
    private var events: EngineEventStream?
    private var eventTask: Task<Void, Never>?

    // MARK: - Orders

    private(set) var orders: [Order] = []
    private(set) var lastReceipt: String?
    var customerName = "Ada Lovelace"
    var customerEmail = "ada@example.com"
    var shipLine = "1 Analytical Way"
    var shipCity = "London"
    var shipRegion = "Greater London"
    var shipPostcode = "N1 9GU"
    var shipCountry = "GB"

    // MARK: - Init

    init() {
        catalog = CatalogService(index: CatalogFixtures.makeIndex())
        pricing = PricingEngine(rateTable: RateTableFixtures.make())

        let directory = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Orders", isDirectory: true)

        let repository: OrderRepository
        if let directory, let files = try? FileOrderRepository(directory: directory) {
            repository = files
        } else {
            repository = InMemoryOrderRepository()
        }

        orderService = OrderService(repository: repository, catalog: catalog, pricing: pricing)
        orders = (try? orderService.orders()) ?? []
        refreshResults()
    }

    // MARK: - Catalogue

    func refreshResults() {
        var query = filter
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        query.keyword = trimmed.isEmpty ? nil : trimmed
        results = catalog.search(query)
        facets = Dictionary(uniqueKeysWithValues: catalog.facetGroups.map { group in
            (group, catalog.descriptors(for: group, within: query))
        })
    }

    func toggle(_ id: FacetItemID, in group: FacetGroup) {
        var set = filter.selections[group] ?? []
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }
        filter.selections[group] = set.isEmpty ? nil : set
        refreshResults()
    }

    func scope(to collection: Collection?) {
        filter.collectionID = collection?.id
        filter.packageName = nil
        scopeTitle = collection?.name ?? "All designs"
        refreshResults()
    }

    func scope(toPackage name: String?) {
        filter.packageName = name
        filter.collectionID = nil
        scopeTitle = name.map { "\($0) package" } ?? "All designs"
        refreshResults()
    }

    func clearAll() {
        filter = .empty
        searchText = ""
        scopeTitle = "All designs"
        refreshResults()
    }

    var activeFacetCount: Int {
        filter.selectedFacetCount
    }

    // MARK: - Opening a design

    func open(_ summary: DesignSummary) {
        guard let detail = catalog.design(id: summary.id) else { return }
        Task { await open(detail) }
    }

    private func open(_ detail: DesignDetail) async {
        isBusy = true
        defer { isBusy = false }

        await closeSession()

        let session = InProcessCADEngine(
            sessionID: SessionID("studio.\(detail.id.rawValue)"),
            catalog: catalog
        )
        let stream = EngineEventStream()
        session.addListener(stream)
        engine = session
        events = stream

        do {
            let configuration = try ConfigurationFactory.makeConfiguration(for: detail, catalog: catalog)
            try await session.open(design: detail, configuration: configuration)
            design = detail
            errorMessage = nil
            subscribe(to: stream)
            await refresh()
        } catch {
            errorMessage = (error as? EngineError)?.description ?? String(describing: error)
        }
    }

    private func subscribe(to stream: EngineEventStream) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in stream.stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    /// Engine pushes are the only thing that moves published state, so the UI
    /// can never show a snapshot that predates a change.
    private func handle(_ event: EngineEvent) async {
        switch event {
        case .configurationChanged(_, let snapshot, _):
            self.snapshot = snapshot
            await refresh()
        case .gemReportUpdated(_, let lines):
            gemReport = lines
        case .undoStateChanged(_, let undo, let redo, _):
            canUndo = undo
            canRedo = redo
        case .designLoaded:
            await refresh()
        case .failed(_, let message):
            errorMessage = message
        case .sessionOpened, .sessionClosed, .selectionChanged,
             .freehandChanged, .renderRequested:
            break
        }
    }

    private func refresh() async {
        guard let engine, let detail = design else { return }
        snapshot = await engine.snapshot()
        gemReport = await engine.gemReport()
        built = try? await engine.build()
        if let configuration = await engine.configuration() {
            quote = try? pricing.quote(configuration: configuration, design: detail)
        }
    }

    func closeSession() async {
        eventTask?.cancel()
        eventTask = nil
        if let events {
            events.finish()
            engine?.removeListener(events)
        }
        await engine?.close()
        engine = nil
        events = nil
    }

    // MARK: - Configuration intents

    var offeredMetals: [Metal] {
        guard let design else { return StandardMetals.all }
        let offered = design.summary.metalIDs.compactMap { StandardMetals.catalog.metal(id: $0) }
        return offered.isEmpty ? StandardMetals.all : offered
    }

    var pairingMetals: [Metal] {
        guard let current = selectedMetal else { return [] }
        return current.pairingOptions(in: StandardMetals.catalog)
    }

    var selectedMetal: Metal? {
        snapshot.flatMap { StandardMetals.catalog.metal(id: $0.metal1ID) }
    }

    var selectedSecondMetal: Metal? {
        snapshot?.metal2ID.flatMap { StandardMetals.catalog.metal(id: $0) }
    }

    var centreSelection: GemSelection? {
        guard let slot = design?.centreSlot?.id else { return nil }
        return gemReport.first { $0.slotIndex == slot }.map { line in
            GemSelection(
                slotIndex: line.slotIndex,
                role: line.role,
                material: line.material,
                shape: line.shape,
                colourID: line.colourID,
                qualityID: line.qualityID,
                carat: line.carat,
                manualSize: line.isManualSize,
                graphicIndex: line.index
            )
        }
    }

    var offeredShapes: [GemShape] {
        guard let material = centreSelection?.material else { return [] }
        let catalogued = gems.shapes(for: material)
        let supported = design?.summary.supportedCentreShapes ?? catalogued
        let offered = catalogued.filter { supported.contains($0) }
        return offered.isEmpty ? catalogued : offered
    }

    var offeredColours: [GemColour] {
        guard let material = centreSelection?.material else { return [] }
        return gems.colours(for: material)
    }

    var offeredQualities: [GemQuality] {
        guard let material = centreSelection?.material else { return [] }
        return gems.qualities(for: material)
    }

    func setMetal(_ metal: Metal, second: Metal? = nil) {
        mutate { engine in try await engine.setMetals(metal1: metal, metal2: second) }
    }

    func setCentreCarat(_ carat: Double) {
        let shape = centreSelection?.shape
        let colour = centreSelection?.colourID
        let quality = centreSelection?.qualityID
        mutate { engine in
            try await engine.setCentreGem(carat: carat, shape: shape, colourID: colour, qualityID: quality)
        }
    }

    func setCentreShape(_ shape: GemShape) {
        updateCentre { $0.shape = shape }
    }

    func setCentreColour(_ colourID: String) {
        updateCentre { $0.colourID = colourID }
    }

    func setCentreQuality(_ qualityID: String) {
        updateCentre { $0.qualityID = qualityID }
    }

    private func updateCentre(_ change: @escaping (inout GemSelection) -> Void) {
        let slot = design?.centreSlot?.id
        mutate { engine in
            guard let configuration = await engine.configuration(),
                  let slot,
                  let index = configuration.gems.firstIndex(where: { $0.slotIndex == slot })
            else { return }
            var gems = configuration.gems
            change(&gems[index])
            try await engine.setGems(gems)
        }
    }

    func setFingerSize(_ usSize: Double) {
        let size = FingerSize(usSize: usSize)
        mutate { engine in try await engine.setFingerSize(size) }
    }

    func toggleRounding() {
        mutate { engine in _ = try await engine.toggleQuarterCaratRounding() }
    }

    func highlightCentre() {
        mutate { engine in await engine.highlightGem(slotIndex: 0) }
    }

    func undo() {
        mutate { engine in try await engine.undo() }
    }

    func redo() {
        mutate { engine in try await engine.redo() }
    }

    /// One path for every mutation, so a failure surfaces in one place and the
    /// state is always re-read afterwards.
    private func mutate(_ body: @escaping @MainActor (InProcessCADEngine) async throws -> Void) {
        guard let engine else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await body(engine)
                errorMessage = nil
                await refresh()
            } catch {
                errorMessage = (error as? EngineError)?.description ?? String(describing: error)
            }
        }
    }

    // MARK: - Order

    func addCurrentRingToOrder() {
        guard let detail = design, let engine else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                guard let configuration = await engine.configuration(),
                      let built = try? await engine.build()
                else { return }
                let order = try orderService.draft(
                    customer: Customer(id: "studio-customer", name: customerName, email: customerEmail),
                    shipTo: ShipTo(
                        name: customerName,
                        line1: shipLine,
                        city: shipCity,
                        region: shipRegion,
                        postalCode: shipPostcode,
                        country: shipCountry
                    ),
                    lines: [(design: detail, configuration: configuration, built: built)]
                )
                orders = try orderService.orders()
                lastReceipt = orderService.receipt(for: order)
                errorMessage = nil
            } catch {
                errorMessage = (error as? OrderError)?.description ?? String(describing: error)
            }
        }
    }

    func submit(_ order: Order) {
        do {
            _ = try orderService.submit(order)
            orders = try orderService.orders()
            errorMessage = nil
        } catch {
            errorMessage = (error as? OrderError)?.description ?? String(describing: error)
        }
    }

    func advance(_ order: Order, to status: OrderStatus) {
        do {
            _ = try orderService.advance(ref: order.ref, to: status)
            orders = try orderService.orders()
        } catch {
            errorMessage = (error as? OrderError)?.description ?? String(describing: error)
        }
    }

    func remove(_ order: Order) {
        do {
            try orderService.delete(ref: order.ref)
            orders = try orderService.orders()
        } catch {
            errorMessage = (error as? OrderError)?.description ?? String(describing: error)
        }
    }
}

// MARK: - Small app-side conveniences

extension Metal {
    /// Metals this one can be paired with for a two-tone ring, excluding itself.
    func pairingOptions(in catalog: MetalCatalog) -> [Metal] {
        catalog.metals.filter { $0.id != id && canPair(with: $0) }
    }
}

extension OrderStatus {
    /// The next states an order may move to, from the model's own rules.
    var forwardStatuses: [OrderStatus] {
        allowedTransitions
    }
}
