//
//  Order.swift
//  JewelcraftKit
//
//  Orders: the payload, its storage, and the state machine that governs it.
//
//  The recovered order contract was deliberately generous — a one-minute open
//  timeout, ten minutes to receive, five to send, two-gigabyte message limits —
//  because an order carries the configuration *and* its rendered images. The
//  payload here keeps that shape: a versioned document containing the
//  configuration, the audited quote, and references to images at the sizes the
//  renderer produces.
//
//  Timestamps and reference numbers are injected rather than taken from the
//  clock and a random source, so an order can be reproduced exactly in a test.
//  A feature that cannot be tested is a feature that will break quietly.
//

import Foundation

// MARK: - Identity

public struct OrderRef: StringIdentifiable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Makes order references: `JWL-20261027-4F2A`.
///
/// Both the date and the token are injected, so a test can assert the exact
/// reference and a caller can swap in a different scheme without touching the
/// order model.
public struct OrderReferenceGenerator {

    public var prefix: String
    private let clock: () -> Date
    private let token: () -> String

    public init(
        prefix: String = "JWL",
        clock: @escaping () -> Date = { Date() },
        token: @escaping () -> String = { OrderReferenceGenerator.randomToken() }
    ) {
        self.prefix = prefix
        self.clock = clock
        self.token = token
    }

    public func make() -> OrderRef {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        let date = formatter.string(from: clock())
        let normalisedToken = token()
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let suffix = normalisedToken.isEmpty ? "0000" : String(normalisedToken.prefix(6))
        return OrderRef("\(prefix)-\(date)-\(suffix)")
    }

    /// A random token from an unambiguous alphabet, so a reference cannot be
    /// misread over the phone (no O/0, no I/1).
    public static func randomToken(length: Int = 4) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }
}

// MARK: - Parties

public struct Customer: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var email: String
    public var phone: String

    public init(id: String, name: String, email: String, phone: String = "") {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
    }

    public var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.contains("@")
    }
}

public struct ShipTo: Codable, Hashable, Sendable {
    public var name: String
    public var line1: String
    public var line2: String
    public var city: String
    public var region: String
    public var postalCode: String
    public var country: String

    public init(
        name: String,
        line1: String,
        line2: String = "",
        city: String,
        region: String,
        postalCode: String,
        country: String
    ) {
        self.name = name
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.region = region
        self.postalCode = postalCode
        self.country = country
    }

    public var isComplete: Bool {
        [name, line1, city, region, postalCode, country].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var singleLine: String {
        var parts = [line1]
        if !line2.isEmpty { parts.append(line2) }
        parts.append(city)
        parts.append(region)
        parts.append(postalCode)
        parts.append(country)
        return parts.joined(separator: ", ")
    }
}

// MARK: - Images

/// A reference to an image attached to an order, at a known size.
public struct OrderImage: Codable, Hashable, Sendable {
    public var key: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var caption: String

    public init(key: String, pixelWidth: Int, pixelHeight: Int, caption: String) {
        self.key = key
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.caption = caption
    }

    public init(key: String, target: RenderTarget, caption: String) {
        self.key = key
        self.pixelWidth = target.pixelSize.width
        self.pixelHeight = target.pixelSize.height
        self.caption = caption
    }

    public var pixelSize: PixelSize {
        PixelSize(width: pixelWidth, height: pixelHeight)
    }
}

// MARK: - Order

public enum OrderStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case submitted
    case inProduction
    case shipped
    case cancelled

    public var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .inProduction: return "In production"
        case .shipped: return "Shipped"
        case .cancelled: return "Cancelled"
        }
    }

    /// The states this one may move to. A shipped order cannot be cancelled,
    /// which is the one rule that protects a customer from a cancelled ring
    /// arriving anyway.
    public var allowedTransitions: [OrderStatus] {
        switch self {
        case .draft: return [.submitted, .cancelled]
        case .submitted: return [.inProduction, .cancelled]
        case .inProduction: return [.shipped, .cancelled]
        case .shipped: return []
        case .cancelled: return []
        }
    }

    public func canTransition(to next: OrderStatus) -> Bool {
        allowedTransitions.contains(next)
    }

    public var isOpen: Bool {
        self == .draft || self == .submitted || self == .inProduction
    }
}

public struct OrderStatusEvent: Codable, Hashable, Sendable {
    public var status: OrderStatus
    public var at: Date
    public var note: String

    public init(status: OrderStatus, at: Date, note: String = "") {
        self.status = status
        self.at = at
        self.note = note
    }
}

public struct OrderLine: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var designID: DesignID
    public var designName: String
    public var spinNumber: SpinNumber
    public var configuration: Configuration
    public var quote: Quote
    public var images: [OrderImage]

    public init(
        id: String,
        designID: DesignID,
        designName: String,
        spinNumber: SpinNumber,
        configuration: Configuration,
        quote: Quote,
        images: [OrderImage] = []
    ) {
        self.id = id
        self.designID = designID
        self.designName = designName
        self.spinNumber = spinNumber
        self.configuration = configuration
        self.quote = quote
        self.images = images
    }

    /// The images an order line should carry, derived from the render targets
    /// rather than listed by hand.
    public static func standardImages(
        for configuration: Configuration,
        designID: DesignID,
        target: RenderTarget = .orderImage
    ) -> [OrderImage] {
        [
            OrderImage(
                key: target.key(for: designID),
                target: target,
                caption: "\(configuration.fingerSize.displayText) configured view"
            )
        ]
    }
}

/// A submitted order. The schema version is part of the document, so a stored
/// order from an older build can be recognised and migrated rather than
/// misread.
public struct Order: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var id: String
    public var ref: OrderRef
    public var schemaVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var customer: Customer
    public var shipTo: ShipTo
    public var lines: [OrderLine]
    public var status: OrderStatus
    public var statusHistory: [OrderStatusEvent]
    public var notes: String
    /// Which channel the order came in on, mirroring the original's
    /// cad/CAM-profile style of tagging where an order originated.
    public var channelCode: String

    public init(
        id: String,
        ref: OrderRef,
        schemaVersion: Int = Order.currentSchemaVersion,
        createdAt: Date,
        updatedAt: Date,
        customer: Customer,
        shipTo: ShipTo,
        lines: [OrderLine],
        status: OrderStatus = .draft,
        statusHistory: [OrderStatusEvent] = [],
        notes: String = "",
        channelCode: String = "studio.ipad"
    ) {
        self.id = id
        self.ref = ref
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.customer = customer
        self.shipTo = shipTo
        self.lines = lines
        self.status = status
        self.statusHistory = statusHistory
        self.notes = notes
        self.channelCode = channelCode
    }

    public var total: Double {
        lines.reduce(0) { $0 + $1.quote.total }
    }

    public var currency: String {
        lines.first?.quote.currency ?? "USD"
    }

    public var formattedTotal: String {
        String(format: "%@ %.2f", currency, total)
    }

    public var itemCount: Int {
        lines.count
    }

    public var totalStoneCount: Int {
        lines.reduce(0) { $0 + $1.configuration.gems.count }
    }

    /// Moves the order to a new state, recording the transition.
    public func transitioning(to next: OrderStatus, at date: Date, note: String = "") throws -> Order {
        guard status.canTransition(to: next) else {
            throw OrderError.invalidTransition(from: status, to: next)
        }
        var copy = self
        copy.status = next
        copy.updatedAt = date
        copy.statusHistory.append(OrderStatusEvent(status: next, at: date, note: note))
        return copy
    }

    /// Whether this order is complete enough to submit.
    public var submissionIssues: [String] {
        var issues: [String] = []
        if lines.isEmpty {
            issues.append("The order has no items.")
        }
        if !customer.isComplete {
            issues.append("The customer's name and e-mail address are required.")
        }
        if !shipTo.isComplete {
            issues.append("A complete shipping address is required.")
        }
        for line in lines where !line.quote.isSelfConsistent {
            issues.append("The quote for \(line.designName) does not add up.")
        }
        for line in lines where line.configuration.validationIssues.isEmpty == false {
            issues.append(contentsOf: line.configuration.validationIssues)
        }
        return issues
    }

    public var canSubmit: Bool {
        submissionIssues.isEmpty
    }
}

// MARK: - Errors

public enum OrderError: Error, Equatable, CustomStringConvertible {
    case invalidTransition(from: OrderStatus, to: OrderStatus)
    case incompleteOrder([String])
    case duplicateReference(OrderRef)
    case notFound(OrderRef)
    case persistence(String)

    public var description: String {
        switch self {
        case .invalidTransition(let from, let to):
            return "An order cannot move from \(from.displayName) to \(to.displayName)."
        case .incompleteOrder(let issues):
            return "The order is not ready to submit: \(issues.joined(separator: "; "))."
        case .duplicateReference(let ref):
            return "An order with reference \(ref.rawValue) already exists."
        case .notFound(let ref):
            return "No order with reference \(ref.rawValue) exists."
        case .persistence(let message):
            return "Order storage failed: \(message)"
        }
    }
}

// MARK: - Storage

public protocol OrderRepository {
    func save(_ order: Order) throws
    func all() throws -> [Order]
    func order(ref: OrderRef) throws -> Order?
    func delete(ref: OrderRef) throws
}

public final class InMemoryOrderRepository: OrderRepository {
    private var storage: [OrderRef: Order] = [:]

    public init(orders: [Order] = []) {
        for order in orders {
            storage[order.ref] = order
        }
    }

    public func save(_ order: Order) throws {
        storage[order.ref] = order
    }

    public func all() throws -> [Order] {
        storage.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func order(ref: OrderRef) throws -> Order? {
        storage[ref]
    }

    public func delete(ref: OrderRef) throws {
        storage.removeValue(forKey: ref)
    }
}

/// Stores orders as one JSON document per order, in a directory.
///
/// Deliberately not a database: an order is a document that gets written once
/// and read whole, and keeping it as a file means a studio can copy, mail or
/// archive an order without an export tool.
public final class FileOrderRepository: OrderRepository {

    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) throws {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for ref: OrderRef) -> URL {
        directory.appendingPathComponent("\(ref.rawValue).json")
    }

    public func save(_ order: Order) throws {
        do {
            let data = try encoder.encode(order)
            try data.write(to: url(for: order.ref), options: .atomic)
        } catch {
            throw OrderError.persistence(String(describing: error))
        }
    }

    public func all() throws -> [Order] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
            var orders: [Order] = []
            for file in files {
                let data = try Data(contentsOf: file)
                orders.append(try decoder.decode(Order.self, from: data))
            }
            return orders.sorted { $0.createdAt < $1.createdAt }
        } catch {
            throw OrderError.persistence(String(describing: error))
        }
    }

    public func order(ref: OrderRef) throws -> Order? {
        let file = url(for: ref)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            return try decoder.decode(Order.self, from: Data(contentsOf: file))
        } catch {
            throw OrderError.persistence(String(describing: error))
        }
    }

    public func delete(ref: OrderRef) throws {
        let file = url(for: ref)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            throw OrderError.persistence(String(describing: error))
        }
    }
}

// MARK: - Service

public final class OrderService {

    private let repository: OrderRepository
    private let catalog: CatalogService
    private let pricing: PricingEngine
    private let references: OrderReferenceGenerator
    private let clock: () -> Date

    public init(
        repository: OrderRepository,
        catalog: CatalogService,
        pricing: PricingEngine,
        references: OrderReferenceGenerator = OrderReferenceGenerator(),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.catalog = catalog
        self.pricing = pricing
        self.references = references
        self.clock = clock
    }

    /// Starts a draft order for a set of configured lines.
    ///
    /// The quote is produced here rather than accepted from the caller, so an
    /// order cannot carry a total that was never derived from the model.
    public func draft(
        customer: Customer,
        shipTo: ShipTo,
        lines: [(design: DesignDetail, configuration: Configuration, built: BuiltRing)],
        notes: String = "",
        discountPercent: Double = 0
    ) throws -> Order {
        let now = clock()
        let ref = references.make()
        var orderLines: [OrderLine] = []

        for (index, entry) in lines.enumerated() {
            let quote = try pricing.quote(
                configuration: entry.configuration,
                design: entry.design,
                built: entry.built,
                discountPercent: discountPercent,
                quoteID: "\(ref.rawValue)-\(index + 1)",
                createdAt: now
            )
            orderLines.append(OrderLine(
                id: "\(ref.rawValue)-line-\(index + 1)",
                designID: entry.design.id,
                designName: entry.design.summary.name,
                spinNumber: entry.design.summary.spinNumber,
                configuration: entry.configuration,
                quote: quote,
                images: OrderLine.standardImages(
                    for: entry.configuration,
                    designID: entry.design.id
                )
            ))
        }

        let order = Order(
            id: ref.rawValue,
            ref: ref,
            createdAt: now,
            updatedAt: now,
            customer: customer,
            shipTo: shipTo,
            lines: orderLines,
            status: .draft,
            statusHistory: [OrderStatusEvent(status: .draft, at: now, note: "Draft created")],
            notes: notes
        )

        try repository.save(order)
        return order
    }

    /// Submits a draft, validating it first.
    public func submit(_ order: Order) throws -> Order {
        let issues = order.submissionIssues
        guard issues.isEmpty else {
            throw OrderError.incompleteOrder(issues)
        }
        let submitted = try order.transitioning(
            to: .submitted,
            at: clock(),
            note: "Order submitted for \(order.formattedTotal)"
        )
        try repository.save(submitted)
        return submitted
    }

    /// Moves a stored order to a new state.
    @discardableResult
    public func advance(ref: OrderRef, to status: OrderStatus, note: String = "") throws -> Order {
        guard let order = try repository.order(ref: ref) else {
            throw OrderError.notFound(ref)
        }
        let updated = try order.transitioning(to: status, at: clock(), note: note)
        try repository.save(updated)
        return updated
    }

    public func orders() throws -> [Order] {
        try repository.all()
    }

    public func order(ref: OrderRef) throws -> Order? {
        try repository.order(ref: ref)
    }

    public func openOrders() throws -> [Order] {
        try repository.all().filter { $0.status.isOpen }
    }

    /// Attaches rendered images to a stored order's line, once the client has
    /// produced them. The engine requests renders; this is where they land.
    @discardableResult
    public func attach(images: [OrderImage], toLineAt index: Int, ref: OrderRef) throws -> Order {
        guard var order = try repository.order(ref: ref) else {
            throw OrderError.notFound(ref)
        }
        guard order.lines.indices.contains(index) else {
            throw OrderError.notFound(ref)
        }
        order.lines[index].images = images
        order.updatedAt = clock()
        try repository.save(order)
        return order
    }

    /// A human-readable receipt, for the order summary and for tests that need
    /// to see the whole document at once.
    public func receipt(for order: Order) -> String {
        var lines: [String] = []
        lines.append("Order \(order.ref.rawValue) — \(order.status.displayName)")
        lines.append("Customer: \(order.customer.name) <\(order.customer.email)>")
        lines.append("Ship to: \(order.shipTo.singleLine)")
        for line in order.lines {
            lines.append("  • \(line.designName) [\(line.spinNumber.rawValue)]")
            lines.append("    \(line.configuration.fingerSize.displayText), "
                + "\(line.configuration.metal1.displayName), "
                + "\(line.configuration.gems.count) stone(s)")
            lines.append("    \(line.quote.formattedTotal) "
                + "(metal \(line.quote.total(for: .metal)), "
                + "stones \(line.quote.total(for: .stone)), "
                + "labour \(line.quote.total(for: .labour)))")
            for image in line.images {
                lines.append("    image: \(image.key) at \(image.pixelWidth)×\(image.pixelHeight)")
            }
        }
        lines.append("Total: \(order.formattedTotal)")
        return lines.joined(separator: "\n")
    }
}
