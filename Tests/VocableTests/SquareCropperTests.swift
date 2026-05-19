//
//  SquareCropperTests.swift
//  VocableTests
//

import XCTest
import UIKit
@testable import Vocable

final class SquareCropperTests: XCTestCase {

    func test_centerSquare_onSquareImage_returnsSameDimensions() {
        let image = makeImage(width: 100, height: 100, color: .red)
        let cropped = SquareCropper.centerSquare(image)
        XCTAssertEqual(cropped.size, CGSize(width: 100, height: 100))
    }

    func test_centerSquare_onLandscapeImage_returnsHeightSidedSquare() {
        let image = makeImage(width: 200, height: 100, color: .blue)
        let cropped = SquareCropper.centerSquare(image)
        XCTAssertEqual(cropped.size, CGSize(width: 100, height: 100))
    }

    func test_centerSquare_onPortraitImage_returnsWidthSidedSquare() {
        let image = makeImage(width: 80, height: 240, color: .green)
        let cropped = SquareCropper.centerSquare(image)
        XCTAssertEqual(cropped.size, CGSize(width: 80, height: 80))
    }

    func test_centerSquare_preservesCenterColor() {
        // Paint left half red and right half blue. After center-square crop
        // of a 200x100 image, the result is 100x100 and centered, so the
        // crop straddles the boundary — at the leftmost edge of the crop
        // we expect red, at the rightmost blue.
        let size = CGSize(width: 200, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }

        let cropped = SquareCropper.centerSquare(image)
        XCTAssertEqual(cropped.size, CGSize(width: 100, height: 100))

        let leftPixel = pixelColor(in: cropped, at: CGPoint(x: 2, y: 50))
        let rightPixel = pixelColor(in: cropped, at: CGPoint(x: 98, y: 50))

        XCTAssertEqual(leftPixel.dominantChannel, .red)
        XCTAssertEqual(rightPixel.dominantChannel, .blue)
    }

    // MARK: - Helpers

    private func makeImage(width: CGFloat, height: CGFloat, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        }
    }

    private struct Pixel {
        enum Channel { case red, green, blue }
        let r, g, b: UInt8
        var dominantChannel: Channel {
            if r >= g && r >= b { return .red }
            if g >= r && g >= b { return .green }
            return .blue
        }
    }

    private func pixelColor(in image: UIImage, at point: CGPoint) -> Pixel {
        guard let cgImage = image.cgImage else { return Pixel(r: 0, g: 0, b: 0) }
        var data: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: &data,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return Pixel(r: 0, g: 0, b: 0) }
        context.draw(
            cgImage,
            in: CGRect(x: -point.x, y: -(CGFloat(cgImage.height) - point.y - 1), width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
        return Pixel(r: data[0], g: data[1], b: data[2])
    }
}
