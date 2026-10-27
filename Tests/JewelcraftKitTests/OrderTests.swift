//
//  OrderTests.swift
//  JewelcraftKitTests
//
//  Orders: the document a workshop receives, and the status machine it moves
//  through.
//
//  Two properties are tested rather than assumed. An order's total is derived
//  from a quote the service produced, never accepted from a caller. And a draft
//  cannot be submitted until it names a customer and a place to ship to, because
//  the cost of getting that wrong is a ring made for nobody.
//

import XCTest
@testable import JewelcraftKit

final class OrderTests: XCTestCase {

    private let catalog = CatalogService(index: CatalogFixtures.makeIndex())
    private let pricing = PricingEngine(rateTable: RateTableFixtures.make())

    private func configured(_ designID: String) throws -> (DesignDetail, Configuration, BuiltRing) {
        let design = try XCTUnwrap(catalog.design(id: DesignID(designID)))
        let configuration = try ConfigurationFactory.makeConfiguration(for: design, catalog: catalog)
        let built = RingBuilder.build(
            designID: design.id,
            parameters: InProcessCADEngine.parameters(for: design, configuration: configuration),
            plan: InProcessCADEngine.gemPlan(for: design, configuration: configuration),
            metal: configuration.metal1,
            metal2: configuration.metal2
        )
        return (design, configuration, built)
    }

    private func makeService(
        repository: OrderRepository = InMemoryOrderRepository()
    ) -> OrderService {
        OrderService(
            repository: repository,
            catalog: catalog,
            pricing: pricing,
            references: OrderReferenceGenerator(prefix: "JW", clock: { Date(timeIntervalSince1970: 1_800_000_000) }),
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private func draft(_ service: OrderService, designID: String = "JWL-1005") throws -> Order {
        let (design, configuration, built) = try configured(designID)
        return try service.draft(
            customer: Customer(id: "c-1", name: "Ada Lovelace", email: "ada@example.com", phone: "555-0100"),
            shipTo: ShipTo(name: "Ada Lovelace", line1: "1 Analytical Way", line2: "",
                           city: "London", region: "LDN", postalCode: "N1", country: "GB"),
            lines: [(design: design, configuration: configuration, built: built)]
        )
    }

    func testADraftOrderCarriesAQuoteAndProductionImages() throws {
        let order = try draft(makeService())

        XCTAssertEqual(order.status, .draft)
        XCTAssertEqual(order.lines.count, 1)
        XCTAssertGreaterThan(order.total, 0)
        XCTAssertEqual(order.itemCount, 1)
        XCTAssertEqual(order.totalStoneCount, 3)
        XCTAssertTrue(order.lines[0].quote.isSelfConsistent)
        XCTAssertEqual(order.lines[0].images.count, 1)

        // The order image is the wide tile at twice linear scale.
        let orderImage = try XCTUnwrap(order.lines[0].images.first)
        XCTAssertEqual(orderImage.pixelWidth, 2480)
        XCTAssertEqual(orderImage.pixelHeight, 1200)
        XCTAssertEqual(order.currency, "USD")
    }

    func testSubmissionAdvancesTheStatusAndRecordsHistory() throws {
        let service = makeService()
        let order = try draft(service)
        XCTAssertTrue(order.submissionIssues.isEmpty)

        let submitted = try service.submit(order)
        XCTAssertEqual(submitted.status, .submitted)
        XCTAssertEqual(submitted.statusHistory.count, 2)
        XCTAssertTrue(submitted.statusHistory.last?.note.contains("Order submitted") ?? false)

        let advanced = try service.advance(ref: submitted.ref, to: .inProduction)
        XCTAssertEqual(advanced.status, .inProduction)
        XCTAssertEqual(try service.openOrders().count, 1)
    }

    func testOnlyTheDeclaredTransitionsAreAllowed() {
        XCTAssertTrue(OrderStatus.draft.canTransition(to: .submitted))
        XCTAssertTrue(OrderStatus.draft.canTransition(to: .cancelled))
        XCTAssertFalse(OrderStatus.draft.canTransition(to: .shipped))
        XCTAssertFalse(OrderStatus.shipped.canTransition(to: .draft))
    }

    func testAnIllegalTransitionIsRefusedAtTheServiceBoundary() throws {
        let service = makeService()
        let order = try draft(service)
        XCTAssertThrowsError(try service.advance(ref: order.ref, to: .shipped)) { error in
            guard let orderError = error as? OrderError,
                  case .invalidTransition = orderError else {
                return XCTFail("expected an invalid transition, got \(error)")
            }
        }
    }

    func testAnIncompleteOrderCannotBeSubmitted() throws {
        let service = makeService()
        let (design, configuration, built) = try configured("JWL-1001")

        let order = try service.draft(
            customer: Customer(id: "c-2", name: "", email: ""),
            shipTo: ShipTo(name: "", line1: "", line2: "", city: "", region: "", postalCode: "", country: ""),
            lines: [(design: design, configuration: configuration, built: built)]
        )

        XCTAssertFalse(order.canSubmit)
        XCTAssertFalse(order.submissionIssues.isEmpty)
        XCTAssertThrowsError(try service.submit(order)) { error in
            guard let orderError = error as? OrderError,
                  case .incompleteOrder = orderError else {
                return XCTFail("expected an incomplete order, got \(error)")
            }
        }
    }

    func testOrdersPersistToDiskAndReloadIdentically() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("jewelcraft-orders-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = try FileOrderRepository(directory: directory)
        let service = makeService(repository: repository)
        let submitted = try service.submit(draft(service, designID: "JWL-1013"))

        let reloaded = try XCTUnwrap(try repository.order(ref: submitted.ref))
        XCTAssertEqual(reloaded.ref, submitted.ref)
        XCTAssertEqual(reloaded.total, submitted.total, accuracy: 1e-9)
        XCTAssertEqual(reloaded.lines.count, 1)
        XCTAssertEqual(reloaded.customer.email, "ada@example.com")
        XCTAssertEqual(reloaded.status, .submitted)
        XCTAssertEqual(reloaded.lines[0].configuration.designID, DesignID("JWL-1013"))
    }

    func testAReceiptNamesTheOrderItsLinesAndItsTotal() throws {
        let service = makeService()
        let order = try draft(service)
        let receipt = service.receipt(for: order)

        XCTAssertTrue(receipt.contains(order.ref.rawValue))
        XCTAssertTrue(receipt.contains("Ada Lovelace"))
        XCTAssertTrue(receipt.contains(order.formattedTotal))
        XCTAssertTrue(receipt.contains("JWL-1005"))
    }

    func testDuplicateReferencesAreRefusedByTheRepository() throws {
        let repository = InMemoryOrderRepository()
        let service = makeService(repository: repository)
        let order = try draft(service)
        XCTAssertNoThrow(try repository.save(order))
        // Saving the same document twice is an update, not a duplicate.
        XCTAssertNoThrow(try repository.save(order))
        XCTAssertEqual(try repository.all().count, 1)
    }

    func testOnlyAnOrderThatHasNotEnteredTheWorkshopCanBeRemoved() throws {
        // Deterministic references, so this test can name the documents it made.
        var issued = 0
        let service = OrderService(
            repository: InMemoryOrderRepository(),
            catalog: catalog,
            pricing: pricing,
            references: OrderReferenceGenerator(
                prefix: "JW",
                clock: { Date(timeIntervalSince1970: 1_800_000_000) },
                token: {
                    issued += 1
                    return String(format: "%04d", issued)
                }
            ),
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let first = try draft(service, designID: "JWL-1005")
        XCTAssertEqual(first.ref.rawValue, "JW-20270115-0001")
        XCTAssertEqual(try service.orders().count, 1)

        // A draft is the studio's own work in progress, so it can be thrown away.
        try service.delete(ref: first.ref)
        XCTAssertTrue(try service.orders().isEmpty)
        XCTAssertNil(try service.order(ref: first.ref))

        // Once submitted, the order is the workshop's record of the job.
        let submitted = try service.submit(try draft(service, designID: "JWL-1005"))
        XCTAssertThrowsError(try service.delete(ref: submitted.ref)) { error in
            guard let orderError = error as? OrderError,
                  case .notDeletable(let status) = orderError else {
                return XCTFail("expected a not-deletable refusal, got \(error)")
            }
            XCTAssertEqual(status, .submitted)
        }
        XCTAssertEqual(try service.orders().count, 1)

        // A cancellation is the end of the road, so a cancelled order can go.
        let cancelled = try service.advance(ref: submitted.ref, to: .cancelled)
        XCTAssertEqual(cancelled.status, .cancelled)
        try service.delete(ref: submitted.ref)
        XCTAssertTrue(try service.orders().isEmpty)

        // Removing something that is not there is reported, not ignored.
        XCTAssertThrowsError(try service.delete(ref: submitted.ref)) { error in
            guard let orderError = error as? OrderError,
                  case .notFound = orderError else {
                return XCTFail("expected a not-found refusal, got \(error)")
            }
        }
    }

    func testADefaultedReferenceGeneratorReadsTheServiceClock() throws {
        // No generator is supplied, so the service's own clock stamps the
        // reference: the document's timestamps and its reference agree.
        let service = OrderService(
            repository: InMemoryOrderRepository(),
            catalog: catalog,
            pricing: pricing,
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let order = try draft(service)

        XCTAssertEqual(order.createdAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(order.ref.rawValue.hasPrefix("JWL-20270115-"), order.ref.rawValue)
    }
}
