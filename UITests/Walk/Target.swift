import XCTest

/// What a step acts on: an element found by its accessibility identifier or its label.
///
/// A target lists one or more matches; the first match found on screen wins, so one target
/// can name the same control in every design (`.label("Comments") | .id("dock.comments")`).
/// Identifiers are preferred; a label is used where a part has none. Labels are English: every
/// walk launches the app with `-AppleLanguages (en)`.
struct Target: CustomStringConvertible, Sendable {
    enum Match: Sendable {
        case identifier(String)
        case label(String)
        /// The label contains this text, case-insensitively.
        case labelContains(String)
        /// The label starts with this text.
        case labelPrefix(String)
        /// A text or search field whose label or placeholder starts with this text.
        case field(String)
        /// The accessibility value is exactly this (a collapsed tab bar's "Collapsed").
        case value(String)
    }

    /// Where to look: the whole app, or only inside one kind of bar.
    enum Scope: Sendable {
        case app, tabBar, navigationBar, toolbar, sheet, alert
        /// Inside the element with this label (the command bar is "Navigation").
        case container(String)
    }

    var matches: [Match]
    var type: XCUIElement.ElementType = .any
    var scope: Scope = .app
    /// Which of the elements that match: the first by default, or the last.
    var picksLast = false
    /// Counts as there only while a touch can reach it. For a control that stays in the tree
    /// while it is hidden: the reader's controls are transparent and closed to touches then,
    /// and XCTest lists them all the same.
    var mustBeReachable = false

    static func id(_ identifier: String, _ type: XCUIElement.ElementType = .any) -> Target {
        Target(matches: [.identifier(identifier)], type: type)
    }

    static func label(_ label: String, _ type: XCUIElement.ElementType = .any) -> Target {
        Target(matches: [.label(label)], type: type)
    }

    static func button(_ label: String) -> Target {
        Target(matches: [.label(label)], type: .button)
    }

    static func containing(_ text: String, _ type: XCUIElement.ElementType = .any) -> Target {
        Target(matches: [.labelContains(text)], type: type)
    }

    static func prefix(_ text: String, _ type: XCUIElement.ElementType = .any) -> Target {
        Target(matches: [.labelPrefix(text)], type: type)
    }

    /// Either target: whichever is found first.
    static func | (lhs: Target, rhs: Target) -> Target {
        var both = lhs
        both.matches += rhs.matches
        if lhs.type != rhs.type { both.type = .any }
        return both
    }

    func `in`(_ scope: Scope) -> Target {
        var copy = self
        copy.scope = scope
        return copy
    }

    var last: Target {
        var copy = self
        copy.picksLast = true
        return copy
    }

    var reachable: Target {
        var copy = self
        copy.mustBeReachable = true
        return copy
    }

    var description: String {
        if matches.isEmpty { return "any \(type)" }
        let names = matches.map { match -> String in
            switch match {
            case .identifier(let id): "#\(id)"
            case .label(let label): "“\(label)”"
            case .labelContains(let text): "…\(text)…"
            case .labelPrefix(let text): "\(text)…"
            case .field(let text): "field \(text)…"
            case .value(let value): "value “\(value)”"
            }
        }
        return names.joined(separator: " or ")
    }

    /// The element, which may not exist yet: queries are lazy, so this never waits.
    @MainActor
    func element(in app: XCUIApplication) -> XCUIElement {
        let query = self.query(in: app)
        return picksLast ? query.allElementsBoundByIndex.last ?? query.firstMatch : query.firstMatch
    }

    /// Whether it is there within `timeout` seconds: in the tree and, if it must be
    /// reachable, where a touch reaches it.
    @MainActor
    func appears(in app: XCUIApplication, within timeout: Double) -> Bool {
        let element = element(in: app)
        guard mustBeReachable else { return element.waitForExistence(timeout: timeout) }
        return Self.poll(for: timeout) { element.exists && element.isHittable }
    }

    /// Whether it is gone within `timeout` seconds: out of the tree or, if it must be
    /// reachable, out of a touch's reach.
    @MainActor
    func disappears(from app: XCUIApplication, within timeout: Double) -> Bool {
        let element = element(in: app)
        guard mustBeReachable else {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
            return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
        }
        return Self.poll(for: timeout) { !(element.exists && element.isHittable) }
    }

    /// Asks `holds` every quarter of a second until it is true or `timeout` seconds are over.
    @MainActor
    private static func poll(for timeout: Double, until holds: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while true {
            if holds() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// Every element that matches, in the order of the tree.
    @MainActor
    func query(in app: XCUIApplication) -> XCUIElementQuery {
        root(in: app).descendants(matching: type).matching(predicate)
    }

    @MainActor
    private func root(in app: XCUIApplication) -> XCUIElement {
        switch scope {
        case .app: app
        // An iPad's tabs are buttons at the top, outside any tab bar element.
        case .tabBar: app.tabBars.firstMatch.exists ? app.tabBars.firstMatch : app
        case .navigationBar: app.navigationBars.firstMatch
        case .toolbar: app.toolbars.firstMatch
        case .sheet: app.sheets.firstMatch
        case .alert: app.alerts.firstMatch
        case .container(let label): app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
    }

    /// No matches: any element of the type.
    private var predicate: NSPredicate {
        guard !matches.isEmpty else { return NSPredicate(value: true) }
        return NSCompoundPredicate(orPredicateWithSubpredicates: matches.map { match in
            switch match {
            case .identifier(let id): NSPredicate(format: "identifier == %@", id)
            case .label(let label): NSPredicate(format: "label == %@", label)
            case .labelContains(let text): NSPredicate(format: "label CONTAINS[c] %@", text)
            case .labelPrefix(let text): NSPredicate(format: "label BEGINSWITH %@", text)
            case .field(let text):
                NSPredicate(
                    format: "(elementType == %d OR elementType == %d) AND (label BEGINSWITH %@ OR placeholderValue BEGINSWITH %@)",
                    XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.searchField.rawValue, text, text
                )
            case .value(let value): NSPredicate(format: "value == %@", value)
            }
        })
    }
}
