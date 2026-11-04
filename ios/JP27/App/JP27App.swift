import BackgroundTasks
import SwiftData
import SwiftUI
import TripKit
import UIKit

@main
struct JP27App: App {
    @UIApplicationDelegateAdaptor(JP27AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.activate()
            case .background:
                model.deactivate()
                Self.scheduleRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshID)) {
            // the next one first: if the time runs out below, the chain is not lost
            Self.scheduleRefresh()
            // returns only once reminders, fences and alarms are set
            await model.refreshInBackground()
        }
    }

    nonisolated static let refreshID = "tech.delphyra.jp27.refresh"

    /// Keep reminders rolling and the widget current while the app sleeps.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date().addingTimeInterval(45 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Launch work that has to wait for UIKit. The App struct (and with it AppModel) is built before
/// UIApplicationMain registers the app with the system; CoreLocation started that early is undefined
/// behaviour per Apple DTS, and in practice CLMonitor's init asserted on every relaunch.
final class JP27AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppModel.shared.location.start()
        return true
    }
}

/// Five tabs for what is opened again and again on the road; everything else is one level deeper.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Appearance.key) private var appearance: Appearance = .system
    @Namespace private var zoom

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            // the torii is the trip's front door (an asset; SF Symbols has no torii);
            // the rest are system glyphs chosen for what each tab is for: a route from one point
            // to another for the plan, あ in a speech bubble for the phrasebook, a wallet for money
            Tab("Hôm nay", image: "torii", value: AppTab.today) {
                TodayTab()
            }
            Tab("Bản đồ", systemImage: "map", value: AppTab.map) {
                MapTab()
            }
            Tab("Lịch trình", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", value: AppTab.plan) {
                PlanTab()
            }
            Tab("Sổ tay", systemImage: "character.bubble.ja", value: AppTab.talk) {
                TalkTab()
            }
            Tab("Chi tiêu", systemImage: "wallet.bifold", value: AppTab.spend) {
                SpendTab()
            }
        }
        // the system's own: folds on a scroll down, opens again as the system does. Not on the
        // map, whose panel is the page: scrolling the day in it would fold the bar under a panel
        // that stays where it is.
        .tabBarMinimizeBehavior(model.tab == .map ? .never : .onScrollDown)
        .sensoryFeedback(.page, trigger: model.tab)
        .modifier(NowAccessorySlot(live: model.live.ride != nil || model.next != nil || model.rehearsing))
        .progressiveEdges()
        .presentsSheets()
        .environment(\.zoomSpace, zoom)
        // the first pass sets the window before anything is seen; later ones come from Settings
        .onChange(of: appearance, initial: true) { old, new in
            new.apply(animated: old != new)
        }
        // never lose records quietly: say so the moment the app opens
        .alert("Sổ ghi chép", isPresented: $model.storeAlert) {
            Button("Để sau", role: .cancel) {}
            Button("Xem trong Cài đặt") { model.present(.settings, from: nil) }
        } message: {
            Text(Records.problem ?? "")
        }
        // a write that failed, said where it can be seen: here while no sheet is up, else on the
        // top sheet (`presentsSheets`)
        .saveIssueAlert(level: 0)
        // offline packs made for a tile build the map no longer reads are useless without signal
        .alert("Bản đồ offline cần tải lại", isPresented: Binding(get: { model.offline.needsReload }, set: { model.offline.needsReload = $0 })) {
            Button("Để sau", role: .cancel) {}
            Button("Tải lại") { model.downloads.downloadAllMaps() }
        } message: {
            Text("Nguồn bản đồ vừa đổi, nên các vùng đã tải không còn dùng được khi mất sóng. Nên tải lại khi có Wi‑Fi.")
        }
        // read here, in a view, so the whole app follows when a rehearsal swaps the records
        .modelContainer(model.container)
    }
}

extension View {
    /// "Chưa lưu được": what was not saved and why. "Thử lại" does it again when `retry` is given,
    /// "Để sau" leaves it; without `retry`, only "OK".
    func saveIssueAlert(_ issue: Binding<SaveIssue?>, retry: ((SaveIssue) -> Void)?) -> some View {
        let shown = issue.wrappedValue
        // closing clears only the issue that was shown: one that "Thử lại" just raised again stays
        let presented = Binding(
            get: { issue.wrappedValue != nil },
            set: { if !$0, issue.wrappedValue?.id == shown?.id { issue.wrappedValue = nil } }
        )
        return alert("Chưa lưu được", isPresented: presented, presenting: shown) { failed in
            if let retry {
                Button("Thử lại") { retry(failed) }
                Button("Để sau", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { failed in
            Text("\(failed.what): \(failed.error)")
        }
    }

    /// The app's own alert for a failed write (`AppModel.saveIssue`), on the view in front: `level`
    /// is how many of the app's sheets are under this view (0 for the tabs). An alert cannot come up
    /// from under a sheet, so only the top one shows it.
    func saveIssueAlert(level: Int) -> some View {
        modifier(SaveIssueLayer(level: level))
    }
}

private struct SaveIssueLayer: ViewModifier {
    @Environment(AppModel.self) private var model
    let level: Int

    func body(content: Content) -> some View {
        let front = Binding<SaveIssue?>(
            get: { model.sheets.count == level ? model.saveIssue : nil },
            set: { model.saveIssue = $0 }
        )
        let canRetry = model.saveIssue.map { model.canRetry($0) } ?? false
        content.saveIssueAlert(front, retry: canRetry ? { model.retrySave($0) } : nil)
    }
}

/// The line above the tab bar, shown only while something is happening: a ride being followed,
/// the next stop of a trip day, or a rehearsal (its badge). Before the trip it would only repeat
/// the countdown the home already shows, so the space goes back to content. Hiding it needs iOS
/// 26.1; on 26.0 it stays. Nghe và dịch is not here: it lives in Sổ tay, with the phrasebook it
/// belongs to.
private struct NowAccessorySlot: ViewModifier {
    let live: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: live) { NowAccessory() }
        } else {
            content.tabViewBottomAccessory { NowAccessory() }
        }
    }
}

/// Where every pushed route leads.
struct RouteHost: View {
    let route: Route

    var body: some View {
        switch route {
        case .day(let key): DayView(key: key)
        case .place(let id): PlaceView(id: id)
        case .ride(let id): RideView(id: id)
        case .journal(let key): JournalView(dayKey: key)
        case .food: FoodGuideView()
        case .stays: StaysView()
        case .stay(let id): StayView(id: id)
        case .fuji: FujiView()
        case .trains: TrainsView()
        case .bookings: BookingsView()
        case .handbook: HandbookView()
        case .scenario(let id): ScenarioView(id: id)
        case .budget: BudgetView()
        case .shopping: ShoppingView()
        case .slot(let id): SlotView(id: id)
        case .highlight(let stay, let walk, let index): StayHighlightView(stay: stay, walk: walk, index: index)
        }
    }
}

/// Where every modal leads. Sheets that show a place or a ride carry their own navigation;
/// `presentsSheets` stacks them and grows each out of the control that opened it.
struct SheetHost: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .place(let id):
            // the place page puts its close button after its own actions
            NavigationStack {
                PlaceView(id: id)
                    .navigationDestination(for: Route.self) { RouteHost(route: $0) }
            }
        case .ride(let id):
            NavigationStack {
                RideView(id: id)
                    .navigationDestination(for: Route.self) { RouteHost(route: $0) }
                    .toolbar { CloseButton() }
            }
        case .expense(let placeID, let yen):
            // full height, set by the editor: its keypad needs the room, and a sheet that zooms out
            // of a button reads cleanest when it lands in one place instead of at a half detent
            ExpenseEditor(placeID: placeID, yen: yen)
        case .atPlace(let id):
            NavigationStack {
                AtPlaceView(id: id)
                    .navigationDestination(for: Route.self) { RouteHost(route: $0) }
                    .toolbar { CloseButton() }
            }
        case .menuScan(let id):
            MenuScanView(placeID: id)
                .presentationDetents([.large])
        case .listen:
            ListenView()
                .presentationDetents([.large])
        case .fujiFinder:
            FujiFinderView()
                .presentationDetents([.large])
        case .fujiSpot(let id, let fromMap):
            // the viewpoint's page puts its close button after its own actions
            NavigationStack {
                FujiSpotPage(id: id, fromMap: fromMap)
                    .navigationDestination(for: Route.self) { RouteHost(route: $0) }
                    .navigationDestination(for: FujiPage.self) { FujiPageHost(page: $0) }
            }
        case .journal(let key):
            NavigationStack {
                JournalView(dayKey: key)
                    .toolbar { CloseButton() }
            }
        case .settings:
            SettingsView()
        }
    }
}


