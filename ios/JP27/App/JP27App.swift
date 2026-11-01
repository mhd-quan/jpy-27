import BackgroundTasks
import SwiftData
import SwiftUI
import TripKit

@main
struct JP27App: App {
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

    static let refreshID = "tech.delphyra.jp27.refresh"

    /// Keep reminders rolling and the widget current while the app sleeps.
    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        request.earliestBeginDate = Date().addingTimeInterval(45 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Five tabs for what is opened again and again on the road; everything else is one level deeper.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Hôm nay", systemImage: "sun.max", value: AppTab.today) {
                TodayTab()
            }
            Tab("Bản đồ", systemImage: "map", value: AppTab.map) {
                MapTab()
            }
            Tab("Lịch trình", systemImage: "calendar", value: AppTab.plan) {
                PlanTab()
            }
            Tab("Sổ tay", systemImage: "character.bubble", value: AppTab.talk) {
                TalkTab()
            }
            Tab("Chi tiêu", systemImage: "yensign.circle", value: AppTab.spend) {
                SpendTab()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowAccessory()
        }
        .sheet(item: $model.sheet) { sheet in
            SheetHost(sheet: sheet)
                .environment(model)
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

/// Where every modal leads. Sheets that show a place or a ride carry their own navigation.
struct SheetHost: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .place(let id):
            NavigationStack {
                PlaceView(id: id)
                    .navigationDestination(for: Route.self) { RouteHost(route: $0) }
                    .toolbar { CloseButton() }
            }
        case .ride(let id):
            NavigationStack {
                RideView(id: id)
                    .navigationDestination(for: Route.self) { RouteHost(route: $0) }
                    .toolbar { CloseButton() }
            }
        case .expense(let placeID, let yen):
            ExpenseEditor(placeID: placeID, yen: yen)
                .presentationDetents([.medium, .large])
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

/// The standard close button of a sheet's toolbar.
struct CloseButton: ToolbarContent {
    @Environment(\.dismiss) private var dismiss

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .close) { dismiss() }
        }
    }
}
