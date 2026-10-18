import QuartzCore
import XCTest
@testable import Launchpod

/// Core Animation's built-in filters, created by type name and configured by key.
@MainActor
final class ClassicalLayerFiltersTests: XCTestCase {
    private typealias Reading = CoreAnimationFilterReading

    func testFiltersAreCreatedByTypeName() throws {
        for type in ["multiplyColor", "gaussianBlur", "colorSaturate", "colorMatrix"] {
            let filter = try XCTUnwrap(ClassicalLayerFilters.filter(type: type), type)
            XCTAssertEqual(Reading.type(of: filter), type)
            XCTAssertEqual(filter.value(forKey: "name") as? String, type, "The default name is the type")
        }
    }

    func testMultiplyColorUsesAGenericGray() throws {
        let filter = try XCTUnwrap(ClassicalLayerFilters.multiplyColor(gray: 0.4))
        let color = filter.value(forKey: "inputColor") as! CGColor
        XCTAssertEqual(color, CGColor(gray: 0.4, alpha: 1))
    }

    func testBlurSaturateAndMatrixKeepTheirInputs() throws {
        let blur = try XCTUnwrap(ClassicalLayerFilters.gaussianBlur(radius: 30, hardEdges: true))
        XCTAssertEqual(Reading.number("inputRadius", of: blur), 30)
        XCTAssertEqual(blur.value(forKey: "inputHardEdges") as? Bool, true)
        let soft = try XCTUnwrap(ClassicalLayerFilters.gaussianBlur(radius: 4, hardEdges: false))
        XCTAssertEqual(soft.value(forKey: "inputHardEdges") as? Bool, false)

        let saturate = try XCTUnwrap(ClassicalLayerFilters.colorSaturate(amount: 1.8))
        XCTAssertEqual(try XCTUnwrap(Reading.number("inputAmount", of: saturate)), 1.8, accuracy: 1e-6)

        let matrix: [Float] = (0..<20).map { Float($0) / 10 }
        let colorMatrix = try XCTUnwrap(ClassicalLayerFilters.colorMatrix(matrix))
        XCTAssertEqual(Reading.colorMatrix(of: colorMatrix), matrix)
        XCTAssertNil(ClassicalLayerFilters.colorMatrix([1, 0, 0]), "A colour matrix has exactly 20 values")
    }

    func testBackdropLayerAndGroupBlending() throws {
        let backdrop = try XCTUnwrap(ClassicalLayerFilters.makeBackdropLayer())
        XCTAssertEqual(NSStringFromClass(type(of: backdrop)), "CABackdropLayer")
        let layer = CALayer()
        XCTAssertEqual(layer.value(forKey: "allowsGroupBlending") as? Bool, true, "Core Animation's default")
        ClassicalLayerFilters.disableGroupBlending(layer)
        XCTAssertEqual(layer.value(forKey: "allowsGroupBlending") as? Bool, false)
    }

    func testNamedFiltersAndResampling() {
        XCTAssertEqual(ClassicalLayerFilters.darkenBlendMode, "darkenBlendMode")
        XCTAssertEqual(ClassicalLayerFilters.lanczos.rawValue, "lanczos")
    }
}
