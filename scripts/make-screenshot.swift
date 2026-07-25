#!/usr/bin/env swift
//
// Renders a marketing screenshot of the popover (with representative MOCK data —
// no real usage) into docs/screenshot.png. Self-contained: SwiftUI ImageRenderer
// + AppKit, no assets, no network.
//
// Run from the repo root:  swift scripts/make-screenshot.swift
//
// The layout here mirrors Sources/ClaudeUsageBar/Views/UsagePopoverView.swift.
// Keep them visually in sync if the popover design changes.
//
import AppKit
import SwiftUI

// MARK: - Tiny formatting helpers (mirrors ClaudeUsageKit.Formatting)

func percent(_ v: Double) -> String { "\(Int(v.rounded()))%" }

func durationLong(_ seconds: TimeInterval) -> String {
    let t = Int(seconds.rounded())
    let d = t / 86_400, h = (t % 86_400) / 3600, m = (t % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

func clock(_ date: Date) -> String {
    let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
    return f.string(from: date)
}

struct Window {
    let utilization: Double
    let resetsAt: Date
    var fraction: Double { min(1, max(0, utilization / 100)) }
    func remaining(_ now: Date) -> TimeInterval { max(0, resetsAt.timeIntervalSince(now)) }
}

let brand = Color(red: 0.85, green: 0.46, blue: 0.34)

func meterColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.5: return .green
    case ..<0.75: return .yellow
    case ..<0.9: return .orange
    default: return .red
    }
}

// MARK: - Views

struct Meter: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                if fraction > 0.001 {
                    Capsule().fill(color.gradient)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
        }
        .frame(height: 9)
    }
}

struct Card: View {
    let title: String
    let subtitle: String
    let window: Window
    let now: Date
    let prominent: Bool

    var body: some View {
        let color = meterColor(window.fraction)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(percent(window.utilization))
                    .font(.system(prominent ? .title : .title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            Meter(fraction: window.fraction, color: color)
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.caption2)
                Text("Resets in \(durationLong(window.remaining(now)))").fontWeight(.medium)
                Text("· \(clock(window.resetsAt))").foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct Popover: View {
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(brand)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude Usage").font(.headline)
                    Text("Updated \(clock(now))").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Card(title: "Current session", subtitle: "5-hour limit",
                 window: Window(utilization: 45, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60)),
                 now: now, prominent: true)
            Card(title: "This week", subtitle: "7-day limit",
                 window: Window(utilization: 82, resetsAt: now.addingTimeInterval((2 * 24 + 22) * 3600)),
                 now: now, prominent: false)
            Card(title: "This week · Opus", subtitle: "7-day limit",
                 window: Window(utilization: 25, resetsAt: now.addingTimeInterval((2 * 24 + 22) * 3600)),
                 now: now, prominent: false)
            HStack {
                Label("Refresh", systemImage: "arrow.clockwise").font(.caption)
                Spacer()
                Text("Quit").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
    }
}

struct Canvas: View {
    let now: Date
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.13), Color(red: 0.06, green: 0.06, blue: 0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Popover(now: now)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.16, green: 0.16, blue: 0.18)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                .padding(44)
        }
        .frame(width: 424, height: 500)
        .environment(\.colorScheme, .dark)
    }
}

/// A slice of the macOS menu bar showing how the widget appears at a glance:
/// our gauge + percentage (highlighted) among a few system items.
struct MenuBar: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.46, blue: 0.63), Color(red: 0.34, green: 0.51, blue: 0.69)],
                startPoint: .leading, endPoint: .trailing
            )
            HStack(spacing: 15) {
                Spacer()
                // The widget — subtly highlighted so the eye lands on it.
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.bottom.0percent")
                    Text("30%")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.16)))

                // A few neighboring system items for context.
                Group {
                    Image(systemName: "play.circle")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "switch.2")
                }
                .opacity(0.92)

                Text("Fri Jul 24  9:49 PM")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .frame(width: 560, height: 40)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Render

@MainActor
func writePNG<V: View>(_ view: V, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2 // retina
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to render \(path)\n".utf8))
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(atPath: "docs", withIntermediateDirectories: true)
    writePNG(Canvas(now: Date()), to: "docs/screenshot.png")
    writePNG(MenuBar(), to: "docs/menubar.png")
}
