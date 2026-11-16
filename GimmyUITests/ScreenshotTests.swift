import XCTest

/// Captures the README screenshots from the app's sample data (launch argument -demo).
/// Run by .github/workflows/screenshots.yml, which passes SCREENSHOTS_DIR.
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-demo", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
    }

    func testScreens() {
        let pending = app.buttons["set.pending"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 20))
        settle()
        snap("1-treino")

        // The rest clock only shows in the first screenshot.
        app.buttons["Descartar este descanso sem registrar"].tap()
        pending.tap()
        let cancel = app.buttons["Cancelar"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        settle()
        snap("2-serie")
        cancel.tap()

        app.tabBars.buttons["Histórico"].tap()
        settle()
        snap("3-historico")

        app.tabBars.buttons["Configurar"].tap()
        let costas = app.buttons["routine.Costas"].firstMatch
        XCTAssertTrue(costas.waitForExistence(timeout: 5))
        settle()
        snap("4-treinos")

        costas.tap()
        let exercise = app.buttons["planItem.Lat Pulldown (Machine)"].firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        settle()
        snap("5-treino")

        exercise.tap()
        XCTAssertTrue(app.navigationBars["Lat Pulldown (Machine)"].waitForExistence(timeout: 5))
        settle()
        snap("6-exercicio")
    }

    private func settle() { Thread.sleep(forTimeInterval: 1.2) }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
