import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct QRCodeView: View {
    let value: String
    var size: CGFloat = 280

    var body: some View {
        Group {
            if let image = qrImage(from: value) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(size * 0.08)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .accessibilityLabel("Feedback QR code")
            } else {
                RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size, height: size)
                    .overlay {
                        Text("QR unavailable")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.82))
                    }
            }
        }
    }

    private func qrImage(from value: String) -> UIImage? {
        guard !value.isEmpty else { return nil }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scale = max(12, Int(size / max(output.extent.width, 1)))
        let transformed = output.transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            QRCodeView(value: "https://bananasystems.co.uk/home-video-channel/fb?supportCode=X7K2P9", size: 320)
        }
    }
}
