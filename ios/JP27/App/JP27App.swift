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
        .modelContainer(model.container)
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
            await model.refreshInBackground()
            Self.scheduleRefresh()
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
    @State private var scroll = TabBarScroll()

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
        // folds on a scroll down, opens again on any scroll up (iOS 27 waits for the top: `TabBarScroll`)
        .tabBarMinimizeBehavior(scroll.up ? .never : .onScrollDown)
        .environment(scroll)
        .modifier(NowAccessorySlot(live: model.live.ride != nil || model.next != nil))
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
    }
}

/// The line above the tab bar, shown only while something is happening: a ride being followed or
/// the next stop of a trip day. Before the trip it would only repeat the countdown the home already
/// shows, so the space goes back to content. Hiding it needs iOS 26.1; on 26.0 it stays.
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


