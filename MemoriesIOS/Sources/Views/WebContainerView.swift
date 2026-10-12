import SwiftUI

/// Main screen once logged in: the Memories WebView in "app mode".
///
/// - In native mode the web page is transparent: the background painted here (color sent
///   by `nativex.setThemeColor`) shows behind it and in the safe areas
///   (notch, home indicator), like Android's themed root view.
/// - Logout happens in the web UI (Settings > Account), or from the error screen.
struct WebContainerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: WebViewModel

    init(
        credentials: Credentials,
        server: LocalHTTPServer,
        onSessionRevoked: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: WebViewModel(
            credentials: credentials,
            server: server,
            onSessionRevoked: onSessionRevoked,
            onLogout: onLogout
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Above the web view rather than over it: it must not hide the Memories header.
                if model.showsUnverifiedUpdateBanner && model.state == .ready {
                    UnverifiedUpdateBanner(dismiss: model.dismissUnverifiedUpdateBanner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                MemoriesWebView(model: model)
            }

            switch model.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .downloading(let done, let total):
                DownloadProgressView(done: done, total: total)
            case .failed(let error):
                ErrorView(error: error, retry: model.start, logout: model.onLogout)
            case .ready:
                EmptyView()
            }

            if model.showsBackButton && model.state == .ready {
                BackButton(action: model.goBack)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if let toast = model.toast {
                ToastView(message: toast.message)
                    .id(toast.id)
                    .task(id: toast.id) { await dismiss(toast) }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .animation(.easeInOut(duration: 0.2), value: model.showsBackButton)
        .animation(.easeInOut(duration: 0.25), value: model.showsUnverifiedUpdateBanner)
        .onAppear {
            model.startIfNeeded()
        }
        .onDisappear(perform: model.stop)
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: model.appDidBecomeActive()
            case .background: model.appDidEnterBackground()
            default: break
            }
        }
    }

    private var background: Color {
        model.themeColor.map(Color.init(uiColor:)) ?? Color(.systemBackground)
    }

    /// Hides the toast after 2 s (or 3.5 s for a "long" toast), like Android.
    private func dismiss(_ toast: WebViewModel.Toast) async {
        try? await Task.sleep(nanoseconds: toast.long ? 3_500_000_000 : 2_000_000_000)
        if model.toast == toast { model.toast = nil }
    }
}
