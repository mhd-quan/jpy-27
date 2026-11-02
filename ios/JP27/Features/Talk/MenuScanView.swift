import PhotosUI
import SwiftUI
import TripKit
import Vision
import VisionKit

/// Point the camera at a menu, take the shot: Vision reads every line, lines naming a researched
/// dish are marked by plain string matching against research/menus-*.json, and the rest are
/// translated on the phone.
struct MenuScanView: View {
    @Environment(AppModel.self) private var model
    let placeID: String?

    @State private var scanner = TalkScannerBox()
    @State private var translator = TalkTranslator()
    @State private var photo: UIImage?
    @State private var lines: [TalkMenuLine] = []
    @State private var scanID = UUID()
    @State private var reading = false
    @State private var pick: PhotosPickerItem?
    /// photos read, felt as they land rather than at the shutter: lines found, or nothing at all
    @State private var found = 0
    @State private var blank = 0

    private var place: Place? { model.store.place(placeID) }

    var body: some View {
        NavigationStack {
            Group {
                if let photo {
                    result(photo)
                } else if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    camera
                } else {
                    ContentUnavailableView {
                        Label("Không mở được camera", systemImage: "camera")
                    } actions: {
                        PhotosPicker("Chọn ảnh thực đơn", selection: $pick, matching: .images)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(place.map { "Thực đơn \($0.name)" } ?? "Quét menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseButton()
                ToolbarItem(placement: .topBarLeading) {
                    if photo != nil {
                        Button("Chụp lại", systemImage: "camera") { reset() }
                    } else {
                        PhotosPicker(selection: $pick, matching: .images) {
                            Label("Ảnh có sẵn", systemImage: "photo.on.rectangle")
                        }
                    }
                }
            }
        }
        .talkTranslation(translator)
        .sensoryFeedback(.done, trigger: found)
        .sensoryFeedback(.fail, trigger: blank)
        .onChange(of: pick) {
            guard let item = pick else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await process(image)
                }
                pick = nil
            }
        }
    }

    // MARK: Camera

    private var camera: some View {
        TalkScannerView(box: scanner)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Button {
                    Task { await capture() }
                } label: {
                    Group {
                        if reading { ProgressView() } else { Image(systemName: "camera.fill").font(.system(size: 28, weight: .semibold)) }
                    }
                    .frame(width: 80, height: 80)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(reading)
                .accessibilityLabel("Chụp thực đơn")
                .padding(.bottom, 28)
            }
    }

    private func capture() async {
        guard let controller = scanner.controller, !reading else { return }
        reading = true
        defer { reading = false }
        guard let image = try? await controller.capturePhoto() else { return }
        await process(image)
    }

    private func process(_ image: UIImage) async {
        reading = true
        defer { reading = false }
        let upright = TalkMenuOCR.upright(image)
        let read = await TalkMenuOCR.read(upright)
        let matcher = MenuMatcher(store: model.store, placeID: placeID)
        let matches = matcher.match(lines: read.map(\.text))
        var out = read.enumerated().map { i, l in TalkMenuLine(id: i, text: l.text, rect: l.rect, match: nil) }
        for m in matches where out.indices.contains(m.line) { out[m.line].match = m }
        scanID = UUID()
        lines = out
        photo = upright
        if out.isEmpty { blank += 1 } else { found += 1 }
        for l in out where l.match == nil && TalkMenuOCR.isJapanese(l.text) {
            translator.enqueue(id: key(l), text: l.text)
        }
    }

    private func reset() {
        photo = nil
        lines = []
    }

    private func key(_ l: TalkMenuLine) -> String { "\(scanID.uuidString)-\(l.id)" }

    // MARK: Result

    private func result(_ image: UIImage) -> some View {
        let matched = lines.filter { $0.match != nil }
        let translated = lines.filter { $0.match == nil && translator.translation(key($0)) != nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                TalkMenuPhoto(image: image, lines: lines, translation: { translator.translation(key($0)) })
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                TalkTranslationPackRow(translator: translator)
                if !matched.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Món đã tìm hiểu", trailing: "\(matched.count)")
                        Card {
                            ForEach(Array(matched.enumerated()), id: \.element.id) { i, line in
                                if i > 0 { Divider() }
                                if let m = line.match { matchRow(m) }
                            }
                        }
                    }
                } else if !lines.isEmpty {
                    Text("Không thấy món nào trong danh sách đã tìm hiểu.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !translated.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Các dòng khác")
                        Card {
                            ForEach(Array(translated.enumerated()), id: \.element.id) { i, line in
                                if i > 0 { Divider() }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.text).font(.subheadline).environment(\.locale, Locale(identifier: "ja_JP"))
                                    Text(translator.translation(key(line)) ?? "").font(.body)
                                    if let yen = JapaneseText.price(in: line.text) {
                                        YenText(yen: yen).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if reading { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
    }

    private func matchRow(_ m: MenuMatcher.Match) -> some View {
        let price = m.printedYen ?? m.candidate.item.yen
        return VStack(alignment: .leading, spacing: 8) {
            DishRow(item: m.candidate.item)
            HStack(spacing: 8) {
                if let printed = m.printedYen, let researched = m.candidate.item.yen, printed != researched {
                    Tag(text: "Menu ghi \(Fmt.yen(printed))", symbol: printed > researched ? "arrow.up" : "arrow.down", tint: printed > researched ? .orange : .green)
                }
                if placeID == nil, let p = model.store.place(m.candidate.placeID) {
                    Tag(text: p.name, symbol: "fork.knife")
                }
                Spacer(minLength: 0)
                // stacks on the scanner, so the scan is still there after logging; one serving's
                // price (a bowl of ramen is one bowl, whoever is at the table): two servings are
                // typed in the editor
                Button {
                    model.present(.expense(placeID: m.candidate.placeID, yen: price), from: "scan.\(scanID).\(m.line)")
                } label: {
                    Label("Ghi món này", systemImage: "yensign")
                }
                .buttonStyle(.pressable(.bordered))
                .controlSize(.small)
                .sheetSource("scan.\(scanID).\(m.line)")
            }
        }
    }
}

// MARK: - Pieces

/// A recognised line, where it sits on the photo, and the researched dish it names.
struct TalkMenuLine: Identifiable {
    let id: Int
    let text: String
    /// pixels of the upright photo, origin top-left
    let rect: CGRect
    var match: MenuMatcher.Match?
}

/// The frozen photo with labels laid over each line: matched dishes in orange, the rest translated.
private struct TalkMenuPhoto: View {
    let image: UIImage
    let lines: [TalkMenuLine]
    let translation: (TalkMenuLine) -> String?

    var body: some View {
        let pixel = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    let k = geo.size.width / max(1, pixel.width)
                    ForEach(lines) { line in
                        let r = CGRect(x: line.rect.minX * k, y: line.rect.minY * k, width: line.rect.width * k, height: line.rect.height * k)
                        label(line)
                            .frame(maxWidth: max(r.width, 120), alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .position(x: r.minX + max(r.width, 120) / 2, y: r.maxY + 10)
                            .allowsHitTesting(false)
                        if line.match != nil {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.orange, lineWidth: 2)
                                .frame(width: r.width + 6, height: r.height + 6)
                                .position(x: r.midX, y: r.midY)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ảnh thực đơn đã quét")
    }

    @ViewBuilder
    private func label(_ line: TalkMenuLine) -> some View {
        if let m = line.match {
            HStack(spacing: 4) {
                if m.candidate.item.pick == .signature || m.candidate.item.pick == .popular {
                    Image(systemName: "star.fill")
                }
                Text(m.candidate.item.shortVi).lineLimit(1)
                if let yen = m.printedYen ?? m.candidate.item.yen { Text(Fmt.yen(yen)).monospacedDigit() }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange, in: .capsule)
        } else if let vi = translation(line) {
            Text(vi)
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.thinMaterial, in: .rect(cornerRadius: 5))
        }
    }
}

enum TalkMenuOCR {
    struct Read {
        let text: String
        let rect: CGRect
    }

    /// Redraw so pixels match the displayed orientation; Vision then reads it as `.up`.
    static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func read(_ image: UIImage) async -> [Read] {
        guard let cg = image.cgImage else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: cg) else { return [] }
        let size = CGSize(width: cg.width, height: cg.height)
        return observations.compactMap { o in
            guard let text = o.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return Read(text: text, rect: o.boundingBox.toImageCoordinates(size, origin: .upperLeft))
        }
    }

    /// Has kana or kanji: worth translating.
    static func isJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040 ... 0x30FF).contains($0.value) || (0x4E00 ... 0x9FFF).contains($0.value) }
    }
}

/// Keeps a handle on the scanner so the shutter can call `capturePhoto()`.
@Observable final class TalkScannerBox {
    @ObservationIgnored weak var controller: DataScannerViewController?
}

/// VisionKit's live text scanner, highlighting Japanese lines as the camera moves.
struct TalkScannerView: UIViewControllerRepresentable {
    let box: TalkScannerBox

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["ja"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        box.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: ()) {
        vc.stopScanning()
    }
}
