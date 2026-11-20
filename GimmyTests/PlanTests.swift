@testable import Gimmy
import XCTest

final class PlanTests: XCTestCase {
    // MARK: Series and planned sets

    func testSeriesLabelsFollowDropAndRestPause() {
        let kinds = ["", SetKind.drop, "", SetKind.restPause, SetKind.restPause, ""]
        XCTAssertEqual(Series.labels(kinds), ["1", "2", "2.1", "3", "3.1", "3.2"])
        XCTAssertEqual(Series.count(kinds), 3)
        XCTAssertEqual(Series.labels([]), [])
    }

    func testPlannedSetsRoundTripThroughTheSheetColumns() {
        let sets = [
            PlanSet(kind: SetKind.warmup, reps: 15),
            PlanSet(kind: SetKind.normal, reps: 12),
            PlanSet(kind: SetKind.drop, reps: 10),
            PlanSet(kind: SetKind.normal, reps: 8),
        ]
        let cols = PlanSets.columns(sets)
        XCTAssertEqual(cols.series, 3, "the drop part is not a series")
        XCTAssertEqual(cols.reps, "15-12-10-8")
        XCTAssertEqual(cols.kinds, "Aquecimento, Normal, Drop, Normal")
        XCTAssertEqual(PlanSets.configured(kinds: cols.kinds, reps: cols.reps), sets)
    }

    func testConfiguredSetsToleratesHandEdits() {
        XCTAssertNil(PlanSets.configured(kinds: "", reps: "15-12"), "no types: a line the app never configured")
        XCTAssertEqual(PlanSets.configured(kinds: "Drop", reps: "10-8"),
                       [PlanSet(kind: SetKind.drop, reps: 10), PlanSet(kind: SetKind.normal, reps: 8)])
        XCTAssertEqual(PlanSets.configured(kinds: "rest-pause, Super, falha", reps: "10"),
                       [PlanSet(kind: SetKind.restPause, reps: 10), PlanSet(kind: SetKind.normal, reps: 10),
                        PlanSet(kind: SetKind.failure, reps: 10)])
    }

    func testSetsFromTheSeriesAndRepsColumns() {
        XCTAssertEqual(PlanSets.fromSheet(sets: 3, reps: "15-12-8-8").map(\.reps), [15, 12, 8])
        XCTAssertEqual(PlanSets.fromSheet(sets: 4, reps: "12").map(\.reps), [12, 12, 12, 12])
        XCTAssertEqual(PlanSets.fromSheet(sets: nil, reps: "").map(\.reps), [10, 10, 10])
        XCTAssertEqual(PlanSets.fromSheet(sets: 1e12, reps: "8").count, PlanSets.maxSets)
        XCTAssertTrue(PlanSets.fromSheet(sets: 3, reps: "10").allSatisfy { $0.kind == SetKind.normal })
    }

    // MARK: Validity

    private let costasOld = RoutineVersion(name: "Costas", start: nil, end: "2026-11-30", rows: [2])
    private let costasNew = RoutineVersion(name: "Costas", start: "2026-12-01", end: nil, rows: [3])

    func testValidityAndStatus() {
        XCTAssertTrue(costasOld.isValid(on: "2026-11-30"))
        XCTAssertFalse(costasOld.isValid(on: "2026-12-01"))
        XCTAssertFalse(costasNew.isValid(on: "2026-11-30"))
        XCTAssertTrue(costasNew.isValid(on: "2027-06-01"), "no end: the current routine")
        XCTAssertEqual(costasNew.status(today: "2026-11-12"), .upcoming)
        XCTAssertEqual(costasNew.status(today: "2026-12-01"), .current)
        XCTAssertEqual(costasOld.status(today: "2026-12-01"), .ended)
        XCTAssertTrue(RoutineVersion(name: "A", start: nil, end: nil, rows: []).isValid(on: "2000-01-01"))
    }

    func testOverlaps() {
        XCTAssertFalse(costasOld.overlaps(start: "2026-12-01", end: nil))
        XCTAssertTrue(costasOld.overlaps(start: "2026-11-30", end: nil))
        XCTAssertTrue(costasNew.overlaps(start: nil, end: nil))
        XCTAssertFalse(costasNew.overlaps(start: "2026-10-01", end: "2026-11-30"))
    }

    func testRoutineRules() {
        XCTAssertNotNil(RoutineRules.validate(name: "  ", start: "2026-12-01", end: nil))
        XCTAssertNotNil(RoutineRules.validate(name: "Peito", start: "2026-12-01", end: "2026-11-01"))
        XCTAssertNil(RoutineRules.validate(name: "Peito", start: "2026-12-01", end: nil))
        XCTAssertEqual(RoutineRules.group(" Braços  B "), "bracos b")
        XCTAssertEqual(RoutineRules.group("COSTAS"), RoutineRules.group("costas"))
    }

    private typealias Fix = RoutineRules.Fix

    func testANewRoutineEndsTheOneOfItsGroupTheDayBefore() {
        let legacy = RoutineVersion(name: "Costas", start: nil, end: nil, rows: [2])
        let new = RoutineVersion(name: "costas ", start: "2026-12-01", end: nil, rows: [])
        XCTAssertEqual(RoutineRules.resolve([legacy, new], pinned: new.id),
                       .ok([Fix(version: legacy.id, name: "Costas", start: nil, end: "2026-11-30")]),
                       "same group despite case and spaces")
    }

    func testRoutinesThatDontOverlapNeedNothing() {
        XCTAssertEqual(RoutineRules.resolve([costasOld, costasNew], pinned: costasNew.id), .ok([]))
        let peito = RoutineVersion(name: "Peito", start: nil, end: nil, rows: [5])
        XCTAssertEqual(RoutineRules.resolve([costasOld, peito], pinned: peito.id), .ok([]), "other groups never clash")
    }

    func testTheRoutineBeingSavedIsNeverShortened() {
        let earlier = RoutineVersion(name: "Ombro", start: "2026-11-01", end: nil, rows: [9])
        let later = RoutineVersion(name: "Ombro", start: "2026-12-01", end: nil, rows: [12])
        guard case .blocked = RoutineRules.resolve([earlier, later], pinned: earlier.id) else {
            return XCTFail("saving the one that starts first would have to cut it short")
        }
        XCTAssertEqual(RoutineRules.resolve([earlier, later], pinned: later.id),
                       .ok([Fix(version: earlier.id, name: "Ombro", start: "2026-11-01", end: "2026-11-30")]))
    }

    func testRoutinesOfAGroupStartingTheSameDayBlock() {
        let a = RoutineVersion(name: "Braços", start: "2026-12-01", end: nil, rows: [3])
        let b = RoutineVersion(name: "bracos", start: "2026-12-01", end: nil, rows: [])
        guard case .blocked = RoutineRules.resolve([a, b], pinned: b.id) else { return XCTFail("same start") }
        let c = RoutineVersion(name: "Pernas", start: nil, end: nil, rows: [4])
        let d = RoutineVersion(name: "PERNAS", start: nil, end: nil, rows: [])
        guard case .blocked = RoutineRules.resolve([c, d], pinned: d.id) else { return XCTFail("no start on either") }
    }

    func testConflictsMadeOutsideTheAppAreSettledToo() {
        let old = RoutineVersion(name: "Peito", start: nil, end: nil, rows: [7])
        let new = RoutineVersion(name: "Peito", start: "2026-11-20", end: nil, rows: [12])
        let saved = RoutineVersion(name: "Costas", start: "2026-12-01", end: nil, rows: [])
        XCTAssertEqual(RoutineRules.resolve([old, new, saved], pinned: saved.id),
                       .ok([Fix(version: old.id, name: "Peito", start: nil, end: "2026-11-19")]))
    }

    func testOnlyTheOverlapsAreCut() {
        let a = RoutineVersion(name: "Costas", start: nil, end: nil, rows: [2])
        let b = RoutineVersion(name: "Costas", start: "2026-11-01", end: "2026-11-15", rows: [8])
        let c = RoutineVersion(name: "Costas", start: "2026-12-01", end: nil, rows: [])
        XCTAssertEqual(RoutineRules.resolve([a, b, c], pinned: c.id),
                       .ok([Fix(version: a.id, name: "Costas", start: nil, end: "2026-10-31")]),
                       "once a ends before b, it no longer reaches c; b ends before c already")
    }

    func testValidityText() {
        XCTAssertEqual(Fmt.fullDay("2026-12-01"), "01/12/2026")
        XCTAssertEqual(Fmt.validity(nil, nil), "Sem datas definidas")
        XCTAssertEqual(Fmt.validity("2026-12-01", nil), "Desde 01/12/2026")
        XCTAssertEqual(Fmt.validity(nil, "2026-11-30"), "Até 30/11/2026")
        XCTAssertEqual(Fmt.validity("2026-10-01", "2026-11-30"), "01/10/2026 a 30/11/2026")
    }

    // MARK: Versions in the ledger

    private func ledger(registro: [[Cell]] = []) -> Ledger {
        makeLedger(registro: registro, plan: [
            planRow("Costas", order: 2, "Pulldown", sets: 3, reps: "12", rest: 120, end: .text("2026-11-30")),
            planRow("Costas", order: 1, "Row", sets: 4, reps: "15-12-10-6", rest: 120, end: .text("2026-11-30")),
            planRow("Costas", order: 1, "Row", reps: "12-10-8-8", rest: 60, notes: "3ª com drop",
                    kinds: "Aquecimento, Normal, Drop, Normal", start: .number(Double(DayKey.serial("2026-12-01")))),
            planRow("Peito", order: 1, "Supino", sets: 3, reps: "10", start: .text("2026-01-01")),
            planRow("Ombro", order: nil, "", start: .text("2026-11-01")),
        ])
    }

    func testLinesGroupIntoVersions() {
        let l = ledger()
        XCTAssertEqual(l.versions.map(\.id), ["Costas|", "Costas|2026-12-01", "Peito|2026-01-01", "Ombro|2026-11-01"])
        XCTAssertEqual(l.versions[0].rows, [2, 3])
        XCTAssertEqual(l.versions[0].end, "2026-11-30")
        XCTAssertEqual(l.items(of: l.versions[0]).map(\.exercise), ["Row", "Pulldown"], "ordered by the Ordem column")
        XCTAssertTrue(l.items(of: l.versions[3]).isEmpty, "a routine with no exercises yet keeps a placeholder line")
    }

    func testPickerOnlyOffersRoutinesInForce() {
        let l = ledger()
        XCTAssertEqual(l.routines(on: "2026-11-12"), ["Costas", "Peito", "Ombro"])
        XCTAssertEqual(l.routines(on: "2026-10-12"), ["Costas", "Peito"], "Ombro starts in November")
        XCTAssertEqual(l.version(named: "Costas", on: "2026-11-30")?.id, "Costas|")
        XCTAssertEqual(l.version(named: "Costas", on: "2026-12-01")?.id, "Costas|2026-12-01")
        XCTAssertNil(l.version(named: "Ombro", on: "2026-10-31"))
    }

    func testTemplateCopiesTheVersionInForceWithoutLoads() {
        let l = ledger()
        let november = l.template(routine: "Costas", day: "2026-11-20")
        XCTAssertEqual(november.rows.map(\.exercise), ["Row", "Row", "Row", "Row", "Pulldown", "Pulldown", "Pulldown"])

        let december = l.template(routine: "Costas", day: "2026-12-05")
        XCTAssertEqual(december.rows, [
            TemplateRow(exercise: "Row", kind: SetKind.warmup, reps: 12),
            TemplateRow(exercise: "Row", kind: SetKind.normal, reps: 10),
            TemplateRow(exercise: "Row", kind: SetKind.drop, reps: 8),
            TemplateRow(exercise: "Row", kind: SetKind.normal, reps: 8),
        ])
        XCTAssertEqual(l.plannedExercises(december).map(\.sets), [3])
        XCTAssertTrue(l.template(routine: "Ombro", day: "2026-11-20").rows.isEmpty)
        XCTAssertTrue(l.template(routine: "Ombro", day: "2026-10-20").rows.isEmpty, "not in force yet")
    }

    func testConfiguredSetsWinOverTheLastSession() {
        let l = ledger(registro: [
            registroRow("20/11/2026", "Costas", "Row", load: 40, reps: 15),
            registroRow("20/11/2026", "Costas", "Row", load: 40, reps: 15),
        ])
        guard let current = l.version(named: "Costas", on: "2026-12-05"),
              let row = l.items(of: current).first else { return XCTFail("missing version") }
        XCTAssertEqual(l.plannedSets(row, before: "2026-12-05").source, .configured)
        XCTAssertEqual(l.plannedSets(row, before: "2026-12-05").sets.map(\.reps), [12, 10, 8, 8])

        guard let old = l.version(named: "Costas", on: "2026-11-25"),
              let oldRow = l.items(of: old).first else { return XCTFail("missing version") }
        XCTAssertEqual(l.plannedSets(oldRow, before: "2026-11-25").source, .lastSession("2026-11-20"))
        XCTAssertEqual(l.plannedSets(oldRow, before: "2026-11-20").source, .sheet)
    }

    func testRestTargetAndNotesFollowTheVersion() {
        let l = ledger()
        XCTAssertEqual(l.restTarget(exercise: "Row", routine: "Costas", day: "2026-11-20"), 120)
        XCTAssertEqual(l.restTarget(exercise: "Row", routine: "Costas", day: "2026-12-05"), 60)
        XCTAssertEqual(l.planItem(exercise: "Row", routine: "Costas", day: "2026-12-05")?.notes, "3ª com drop")
        XCTAssertNil(l.planItem(exercise: "Pulldown", routine: "Costas", day: "2026-12-05"))
    }

    func testSessionDaysStayInsideTheVersionDates() {
        let l = ledger(registro: [
            registroRow("20/11/2026", "Costas", "Row", load: 40),
            registroRow("05/12/2026", "Costas", "Row", load: 40),
            registroRow("06/12/2026", "Costas", "Row", load: nil),
        ])
        XCTAssertEqual(l.sessionDays(of: l.versions[0]), ["2026-11-20"])
        XCTAssertEqual(l.sessionDays(of: l.versions[1]), ["2026-12-05"], "sets without a load don't count")
        XCTAssertEqual(l.sessionDays(of: l.versions[3]), [])
    }
}
