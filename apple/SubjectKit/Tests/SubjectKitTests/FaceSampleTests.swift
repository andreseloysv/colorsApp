// Geometría de la muestra de piel (sin Vision): mejillas y frente respecto a
// ojos, cejas y labios sintéticos, con giro y casos degenerados.
import CoreGraphics
import XCTest
@testable import SubjectKit

final class FaceSampleTests: XCTestCase {
    /// Cara frontal: ojos en (40, 50) y (60, 50), cejas en y = 42, boca en (50, 72).
    static func frontal() -> FaceLandmarkPoints {
        func ring(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ n: Int = 8) -> [CGPoint] {
            (0..<n).map { k in
                let a = Double(k) / Double(n) * 2 * Double.pi
                return CGPoint(x: cx + rx * cos(a), y: cy + ry * sin(a))
            }
        }
        let contour = (0...10).map { k -> CGPoint in
            let a = Double.pi * Double(k) / 10 // de la sien derecha a la izquierda pasando por la barbilla
            return CGPoint(x: 50 + 22 * cos(a), y: 50 + 40 * sin(a))
        }
        return FaceLandmarkPoints(
            leftEye: ring(40, 50, 4, 2), rightEye: ring(60, 50, 4, 2),
            leftEyebrow: (0..<5).map { CGPoint(x: 35 + 2.5 * Double($0), y: 42) },
            rightEyebrow: (0..<5).map { CGPoint(x: 55 + 2.5 * Double($0), y: 42) },
            outerLips: ring(50, 72, 8, 3), faceContour: contour,
            boundingBox: CGRect(x: 28, y: 36, width: 44, height: 56))
    }

    func rotated(_ lm: FaceLandmarkPoints, degrees: Double) -> FaceLandmarkPoints {
        let a = degrees * Double.pi / 180, c = CGPoint(x: 50, y: 60)
        func r(_ p: CGPoint) -> CGPoint {
            let dx = p.x - c.x, dy = p.y - c.y
            return CGPoint(x: c.x + dx * cos(a) - dy * sin(a), y: c.y + dx * sin(a) + dy * cos(a))
        }
        return FaceLandmarkPoints(leftEye: lm.leftEye.map(r), rightEye: lm.rightEye.map(r),
                                  leftEyebrow: lm.leftEyebrow.map(r), rightEyebrow: lm.rightEyebrow.map(r),
                                  outerLips: lm.outerLips.map(r), faceContour: lm.faceContour.map(r))
    }

    func testFrontalFaceSampleAvoidsEyesBrowsAndLips() throws {
        let lm = Self.frontal()
        let polys = try XCTUnwrap(FaceSample.polygons(lm))
        XCTAssertEqual(polys.count, 3)
        let mask = try XCTUnwrap(FaceSample.mask(lm, width: 100, height: 100, personMask: nil))
        func at(_ x: Int, _ y: Int) -> UInt8 { mask[y * 100 + x] }
        // Mejillas y frente dentro.
        XCTAssertEqual(at(40, 61), 255)
        XCTAssertEqual(at(60, 61), 255)
        XCTAssertEqual(at(50, 38), 255)
        // Ojos, cejas, labios y nariz fuera.
        for p in lm.leftEye + lm.rightEye + lm.leftEyebrow + lm.rightEyebrow + lm.outerLips {
            XCTAssertEqual(at(Int(p.x), Int(p.y)), 0, "landmark \(p)")
        }
        XCTAssertEqual(at(50, 60), 0) // entre las mejillas: nariz
        // Por debajo de la boca y fuera del contorno, nada.
        for y in 76..<100 { for x in 0..<100 { XCTAssertEqual(at(x, y), 0) } }
        let n = MaskOps.nonZero(mask)
        XCTAssertGreaterThan(n, 150)
        // Recorte con la persona: una máscara vacía deja la muestra vacía.
        let clipped = try XCTUnwrap(FaceSample.mask(lm, width: 100, height: 100,
                                                    personMask: [UInt8](repeating: 0, count: 10_000)))
        XCTAssertEqual(MaskOps.nonZero(clipped), 0)
        // Con la persona llena, la erosión de 2 px solo afecta al borde del raster.
        let full = try XCTUnwrap(FaceSample.mask(lm, width: 100, height: 100,
                                                 personMask: [UInt8](repeating: 255, count: 10_000)))
        XCTAssertEqual(full, mask)
    }

    func testRollFollowsTheFace() throws {
        let lm = rotated(Self.frontal(), degrees: 30)
        let mask = try XCTUnwrap(FaceSample.mask(lm, width: 100, height: 100, personMask: nil))
        let a = 30 * Double.pi / 180
        func rot(_ x: Double, _ y: Double) -> (Int, Int) {
            let dx = x - 50, dy = y - 60
            return (Int(50 + dx * cos(a) - dy * sin(a)), Int(60 + dx * sin(a) + dy * cos(a)))
        }
        for (x, y) in [rot(40, 61), rot(60, 61)] { XCTAssertEqual(mask[y * 100 + x], 255, "mejilla (\(x), \(y))") }
        for (x, y) in [rot(40, 50), rot(60, 50), rot(50, 72)] { XCTAssertEqual(mask[y * 100 + x], 0, "(\(x), \(y))") }
    }

    func testDegenerateLandmarksGiveNil() {
        var lm = Self.frontal()
        lm.outerLips = []
        XCTAssertNil(FaceSample.polygons(lm))
        lm = Self.frontal()
        lm.rightEye = lm.leftEye
        XCTAssertNil(FaceSample.polygons(lm))
        lm = Self.frontal()
        lm.outerLips = [CGPoint(x: 70, y: 50)] // boca en la recta de los ojos
        XCTAssertNil(FaceSample.polygons(lm))
    }

    func testConvexHelpers() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertTrue(MaskOps.pointInConvexPolygon(CGPoint(x: 5, y: 5), square))
        XCTAssertTrue(MaskOps.pointInConvexPolygon(CGPoint(x: 10, y: 5), square))
        XCTAssertFalse(MaskOps.pointInConvexPolygon(CGPoint(x: 11, y: 5), square))
        XCTAssertEqual(MaskOps.convexHull(square + [CGPoint(x: 5, y: 5)]).count, 4)
        let shifted = square.map { CGPoint(x: $0.x + 5, y: $0.y) }
        let inter = MaskOps.intersectConvex(square, shifted)
        XCTAssertEqual(inter.map(\.x).min(), 5)
        XCTAssertEqual(inter.map(\.x).max(), 10)
        XCTAssertTrue(MaskOps.intersectConvex(square, square.map { CGPoint(x: $0.x + 20, y: $0.y) }).isEmpty)
        let filled = MaskOps.fillConvexPolygons([square], width: 12, height: 12)
        XCTAssertEqual(MaskOps.nonZero(filled), 100)
    }
}
