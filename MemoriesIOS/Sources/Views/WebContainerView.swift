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
                // Hidden while the photo viewer is open: it would sit over the full-screen photo.
                if model.showsUnverifiedUpdateBanner && model.state == .ready && !model.viewerFullscreen {
                    UnverifiedUpdateBanner(dismiss: model.dismissUnverifiedUpdateBanner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                // Album download progress banner (issue #14): same style as the banner above,
                // pushes the web view down so the user can keep navigating. Hidden while the
                // photo viewer is open (full screen).
                if let progress = model.downloadProgress, !model.viewerFullscreen {
                    DownloadProgressBanner(
                        progress: progress,
                        onTap: model.showDownloadProgressModal,
                        onCancel: model.cancelDownload
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                // Full screen only while the photo viewer is open (issue #13): a zoomed photo
                // then uses the whole screen, safe areas included. The rest of the app keeps
                // the safe-area layout (the web UI does not handle the top inset).
                MemoriesWebView(model: model)
                    .ignoresSafeArea(model.viewerFullscreen ? .all : [])
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

            // Hidden while the photo viewer is open: the viewer has its own back button.
            if model.showsBackButton && model.state == .ready && !model.viewerFullscreen {
                BackButton(action: model.goBack)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if let toast = model.toast {
                ToastView(message: toast.message)
                    .id(toast.id)
                    .task(id: toast.id) { await dismiss(toast) }
            }

            // Full progress modal (issue #14): opened by tapping the banner.
            if model.showsDownloadProgressModal, let progress = model.downloadProgress {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { model.hideDownloadProgressModal() }

                AlbumDownloadProgressView(
                    progress: progress,
                    onClose: model.hideDownloadProgressModal,
                    onCancel: model.cancelDownload
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .animation(.easeInOut(duration: 0.2), value: model.showsBackButton)
        .animation(.easeInOut(duration: 0.25), value: model.showsUnverifiedUpdateBanner)
        .animation(.easeInOut(duration: 0.2), value: model.downloadProgress)
        .animation(.easeInOut(duration: 0.2), value: model.showsDownloadProgressModal)
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
