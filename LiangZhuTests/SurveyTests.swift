import XCTest
import PDFKit
@testable import LiangZhu

final class GeometryTests: XCTestCase {
    func testRectangleAreaAndPerimeter() {
        let room = SurveyRoom(name: "客厅", vertices: SurveyRoom.rectangle(width: 5.2, depth: 4.1), height: 2.8)
        XCTAssertEqual(room.area, 21.32, accuracy: 0.00001)
        XCTAssertEqual(room.perimeter, 18.6, accuracy: 0.00001)
        XCTAssertTrue(SurveyRoom.validPolygon(room.vertices))
    }
    func testConcaveAreaDoesNotUseBoundingBox() {
        let room = SurveyRoom(name: "厨房", vertices: SurveyRoom.lShape(width: 3.2, depth: 2.8, cutWidth: 1, cutDepth: 1), height: 2.8)
        XCTAssertEqual(room.area, 7.96, accuracy: 0.00001)
        XCTAssertEqual(room.perimeter, 12, accuracy: 0.00001)
        XCTAssertTrue(SurveyRoom.validPolygon(room.vertices))
        XCTAssertEqual(SurveyRoom.area(of: room.vertices.reversed()), room.area, accuracy: 0.00001)
    }
    func testRejectsSelfIntersectingAndDuplicateVertices() {
        XCTAssertFalse(SurveyRoom.validPolygon([.init(x: 0, y: 0), .init(x: 4, y: 3), .init(x: 0, y: 3), .init(x: 3, y: 0)]))
        XCTAssertFalse(SurveyRoom.validPolygon([.init(x: 0, y: 0), .init(x: 3, y: 0), .init(x: 3, y: 0), .init(x: 0, y: 3)]))
        XCTAssertFalse(SurveyRoom.validPolygon([.init(x: .nan, y: 0), .init(x: 3, y: 0), .init(x: 0, y: 3)]))
    }
    func testRejectsBacktrackingEdges() {
        let points = [PlanPoint(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 2, y: 0), .init(x: 2, y: 3), .init(x: 0, y: 3)]
        XCTAssertFalse(SurveyRoom.validPolygon(points))
    }
    func testOpeningBoundaryAndHeightValidation() {
        let room = SurveyRoom(name: "测试", vertices: SurveyRoom.rectangle(width: 4, depth: 3), height: 2.8)
        XCTAssertNil(room.openingProblem(Opening(kind: .door, edge: 0, offset: 3.1, width: 0.9, height: 2.1)))
        XCTAssertNotNil(room.openingProblem(Opening(kind: .door, edge: 0, offset: 3.2, width: 0.9, height: 2.1)))
        XCTAssertNotNil(room.openingProblem(Opening(kind: .window, edge: 0, offset: 1, width: 1, height: 1.5, sill: 1.4)))
        XCTAssertNotNil(room.openingProblem(Opening(kind: .door, edge: 4, offset: 0, width: 1, height: 2)))
        XCTAssertNotNil(room.openingProblem(Opening(kind: .door, edge: 0, offset: -1, width: 1, height: 2)))
    }
    func testOverlappingOpeningsAndEditingExistingOpening() {
        let door = Opening(kind: .door, edge: 0, offset: 1, width: 0.9, height: 2.1)
        let room = SurveyRoom(name: "测试", vertices: SurveyRoom.rectangle(width: 4, depth: 3), height: 2.8, openings: [door])
        XCTAssertNil(room.openingProblem(door, excluding: door.id))
        XCTAssertNotNil(room.openingProblem(Opening(kind: .window, edge: 0, offset: 1.5, width: 1, height: 1.5, sill: 0.9)))
        XCTAssertNil(room.openingProblem(Opening(kind: .door, edge: 0, offset: 1.9, width: 0.9, height: 2.1)))
    }
    func testWindowAboveAnotherOpeningDoesNotOverlap() {
        let room = SurveyRoom(name: "测试", vertices: SurveyRoom.rectangle(width: 4, depth: 3), height: 4,
                              openings: [Opening(kind: .door, edge: 0, offset: 1, width: 1, height: 2)])
        XCTAssertNil(room.openingProblem(Opening(kind: .window, edge: 0, offset: 1, width: 1, height: 1, sill: 2.5)))
    }
    func testNetWallAreaDeductsOpenings() {
        let room = SurveyRoom(name: "测试", vertices: SurveyRoom.rectangle(width: 4, depth: 3), height: 2.8,
                              openings: [Opening(kind: .door, edge: 0, offset: 1, width: 0.9, height: 2.1)])
        XCTAssertEqual(room.wallArea, 14 * 2.8 - 0.9 * 2.1, accuracy: 0.00001)
    }
    func testDecimalInputAndUnitConversion() {
        XCTAssertEqual(decimalValue(" 3,25 "), 3.25)
        XCTAssertNil(decimalValue("nan"))
        XCTAssertNil(decimalValue("inf"))
        XCTAssertEqual(DimensionUnit.millimetres.format(1.234), "1234 mm")
    }
    func testExampleIsValidAndCodable() throws {
        let project = SurveyProject.example
        XCTAssertTrue(project.isValid)
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(SurveyProject.self, from: data), project)
    }
}

@MainActor
final class PersistenceAndExportTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("projects.json")
    }
    func testSaveAndReloadRoomsAndOpenings() throws {
        let file = temporaryURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ProjectStore(fileURL: file)
        var project = SurveyProject.example
        project.name = "现场测量"
        XCTAssertTrue(store.save(project))
        let loaded = ProjectStore(fileURL: file)
        XCTAssertEqual(loaded.project(project.id)?.rooms, project.rooms)
        XCTAssertNil(loaded.errorMessage)
    }
    func testCorruptFileIsPreservedAndWritesBlocked() throws {
        let file = temporaryURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("broken data".utf8)
        try original.write(to: file)
        let store = ProjectStore(fileURL: file)
        XCTAssertFalse(store.canWrite)
        XCTAssertFalse(store.save(.example))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testInvalidGeometryIsRejectedBeforeSaving() {
        let file = temporaryURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ProjectStore(fileURL: file)
        var bad = SurveyProject.example
        bad.rooms[0].height = -1
        XCTAssertFalse(store.save(bad))
    }
    func testDeletingProjectPersistsAcrossRelaunch() {
        let file = temporaryURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ProjectStore(fileURL: file)
        store.projects.forEach { store.delete($0.id) }
        XCTAssertTrue(ProjectStore(fileURL: file).projects.isEmpty)
    }
    func testBackupRestoreMakesANewProjectWithoutOverwriting() throws {
        let file = temporaryURL()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ProjectStore(fileURL: file)
        let project = store.projects[0]
        let backup = try SurveyExporter.backup(project: project)
        defer { try? FileManager.default.removeItem(at: backup.deletingLastPathComponent()) }
        XCTAssertTrue(store.importBackup(backup))
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertNotEqual(store.projects[0].id, project.id)
        XCTAssertEqual(store.projects[0].rooms, project.rooms)
    }
    func testPDFContainsEachRoomAndPaginatedNotes() throws {
        var project = SurveyProject.example
        project.rooms[0].notes = String(repeating: "现场备注：水电位置需要复核。", count: 150)
        let url = try SurveyExporter.pdf(project: project)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, project.rooms.count)
        let allText = document.string ?? ""
        for room in project.rooms { XCTAssertTrue(allText.contains(room.name)) }
        XCTAssertTrue(allText.contains("净墙面"))
    }
}
