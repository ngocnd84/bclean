import SwiftUI

struct RootView: View {
    @EnvironmentObject var library: LibraryStore
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        Group {
            if !onboarded {
                OnboardingView { onboarded = true }
            } else if !library.hasAccess {
                PermissionView()
            } else {
                MainTabView()
            }
        }
        .animation(.default, value: onboarded)
        .animation(.default, value: library.hasAccess)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label(L("tab_clean"), systemImage: "sparkles") }
            SwipeMonthsView()
                .tabItem { Label(L("tab_swipe"), systemImage: "hand.draw") }
            VideoListView()
                .tabItem { Label(L("tab_videos"), systemImage: "film") }
            SettingsView()
                .tabItem { Label(L("tab_settings"), systemImage: "gearshape") }
        }
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        ("sparkles", "onb1_title", "onb1_body"),
        ("lock.shield", "onb2_title", "onb2_body"),
        ("hand.draw", "onb3_title", "onb3_body")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: pages[i].icon)
                            .font(.system(size: 88, weight: .semibold))
                            .foregroundStyle(Theme.gradient)
                        Text(L(pages[i].title))
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(L(pages[i].body))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    Analytics.log("onboarding_done")
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? L("continue") : L("get_started"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

struct PermissionView: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundStyle(Theme.gradient)
            Text(L("perm_title"))
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(L("perm_body"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Label(L("perm_privacy"), systemImage: "lock.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.teal)
            Spacer()
            if library.isDenied {
                Text(L("perm_denied"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Text(L("open_settings")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Text(L("perm_allow")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
