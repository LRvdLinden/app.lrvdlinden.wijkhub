import SwiftUI

/// Het BuurtHub-beeldmerk "Thuisballon": huisje + tekstballon met drie puntjes (64 × 64-raster).
struct BrandMark: View {
    enum Style { case onLight, onGreen }
    var style: Style = .onLight

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 64
            let dx = (size.width - 64 * s) / 2, dy = (size.height - 64 * s) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * s, y: dy + y * s) }

            var house = Path()
            house.move(to: p(32, 7))
            house.addLine(to: p(56.4, 26.6))
            house.addQuadCurve(to: p(54.8, 31.3), control: p(58.2, 30.6))
            house.addLine(to: p(52, 31.3))
            house.addLine(to: p(52, 46))
            house.addQuadCurve(to: p(46, 52), control: p(52, 52))
            house.addLine(to: p(29, 52))
            house.addLine(to: p(18, 60.5))
            house.addLine(to: p(18, 52))
            house.addQuadCurve(to: p(12, 46), control: p(12, 52))
            house.addLine(to: p(12, 31.3))
            house.addLine(to: p(9.2, 31.3))
            house.addQuadCurve(to: p(7.6, 26.6), control: p(5.8, 30.6))
            house.closeSubpath()

            let body: Color = style == .onLight ? Theme.green : .white
            let dots: Color = style == .onLight ? .white : Theme.green
            ctx.fill(house, with: .color(body))
            for (i, x) in [22.5, 32.0, 41.5].enumerated() {
                let r: CGFloat = 3.6
                let dot = Path(ellipseIn: CGRect(x: dx + (x - r) * s, y: dy + (39 - r) * s, width: 2 * r * s, height: 2 * r * s))
                ctx.fill(dot, with: .color(i == 1 ? Theme.lime : dots))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Beeldmerk + woordmerk "BuurtHub" (Buurt donkergroen, Hub lichtgroen).
struct BrandLogo: View {
    var markSize: CGFloat = 44
    var onGreen = false

    var body: some View {
        HStack(spacing: markSize * 0.25) {
            BrandMark(style: onGreen ? .onGreen : .onLight)
                .frame(width: markSize, height: markSize)
            (Text(verbatim: "Buurt").foregroundStyle(onGreen ? Color.white : Theme.green)
             + Text(verbatim: "Hub").foregroundStyle(onGreen ? Color(light: 0xB9E08A, dark: 0xB9E08A) : Theme.lime))
                .font(.system(size: markSize * 0.82, weight: .heavy, design: .rounded))
                .kerning(-markSize * 0.02)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "BuurtHub"))
    }
}

#Preview {
    VStack(spacing: 24) {
        BrandLogo(markSize: 56)
        BrandLogo(markSize: 40, onGreen: true).padding().background(Theme.green)
    }
}
