import SwiftUI

public struct DayShapeView: View {
  private let shape: DayShape
  private let tint: Color

  public init(shape: DayShape, tint: Color) {
    self.shape = shape
    self.tint = tint
  }

  public var body: some View {
    ZStack {
      switch shape {
      case .cone:
        ConeShape(tint: tint)
      case .pennant:
        PennantShape(tint: tint)
      case .mast:
        MastShape(tint: tint)
      }
    }
    .geometryGroup()
  }
}

private struct ConeShape: View {
  let tint: Color

  var body: some View {
    ZStack {
      ConeFill()
        .fill(tint)
      ConeStroke()
        .stroke(tint, style: StrokeStyle(lineWidth: 3.7, lineCap: .round, lineJoin: .round))
    }
  }
}

private struct PennantShape: View {
  let tint: Color

  var body: some View {
    ZStack {
      PennantFill()
        .fill(tint)
      PennantStroke()
        .stroke(tint, style: StrokeStyle(lineWidth: 3.7, lineCap: .round, lineJoin: .round))
    }
  }
}

private struct MastShape: View {
  let tint: Color

  var body: some View {
    MastStroke()
      .stroke(tint, style: StrokeStyle(lineWidth: 3.7, lineCap: .round, lineJoin: .round))
  }
}

private struct ConeFill: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let x = rect.minX + rect.width / 2
    path.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.1))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.minY + rect.height * 0.41))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.23, y: rect.minY + rect.height * 0.41))
    path.closeSubpath()
    return path
  }
}

private struct ConeStroke: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let x = rect.minX + rect.width / 2
    let baseY = rect.minY + rect.height * 0.41
    path.move(to: CGPoint(x: x, y: baseY))
    path.addLine(to: CGPoint(x: x, y: rect.maxY))
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.73))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.27, y: rect.minY + rect.height * 0.73))
    return path
  }
}

private struct PennantFill: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let poleX = rect.minX + rect.width / 2
    path.move(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.17))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.17, y: rect.minY + rect.height * 0.28))
    path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.39))
    path.closeSubpath()
    return path
  }
}

private struct PennantStroke: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let poleX = rect.minX + rect.width / 2
    path.move(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.1))
    path.addLine(to: CGPoint(x: poleX, y: rect.maxY - rect.height * 0.01))
    return path
  }
}

private struct MastStroke: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let poleX = rect.minX + rect.width / 2
    let yardY = rect.minY + rect.height * 0.36
    path.move(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.1))
    path.addLine(to: CGPoint(x: poleX, y: rect.maxY - rect.height * 0.01))
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: yardY))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: yardY))
    path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: yardY))
    path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3, y: yardY + rect.height * 0.12))
    path.move(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: yardY))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: yardY + rect.height * 0.12))
    return path
  }
}
