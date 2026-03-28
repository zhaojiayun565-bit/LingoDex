//
//  ContentView.swift
//  LingoDex
//
//  Created by Jia Yun Zhao on 2026-03-19.
//

import AVFoundation
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        MainTabContainer()
    }
}

private struct MainTabContainer: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = AppViewModel(auth: Dependencies.live.auth)
    private let deps = Dependencies.live
    @State private var capturesViewModel: CapturesViewModel?
    @State private var meViewModel = MeViewModel(deps: Dependencies.live)
    @State private var practiceViewModel = PracticeViewModel(deps: Dependencies.live)
    @State private var worldViewModel = WorldViewModel(deps: Dependencies.live)
    @State private var isShowingCaptureFlow = false
    @State private var preWarmedCameraSession: (session: AVCaptureSession, photoOutput: AVCapturePhotoOutput?)?
    @State private var isShowingPhotoPicker = false
    @State private var isKeyboardVisible = false
    @State private var recognitionWarmUpTask: Task<Void, Never>?
    @State private var didRunStartupWarmups = false
    @State private var isActiveRefreshInFlight = false
    @State private var lastActiveRefreshAt = Date.distantPast

    var body: some View {
        Group {
            if let capturesViewModel {
                mainContent(capturesViewModel: capturesViewModel)
            } else {
                loadingState
            }
        }
        .task {
            guard capturesViewModel == nil else { return }
            let viewModel = CapturesViewModel(deps: deps)
            capturesViewModel = viewModel

            Task(priority: .utility) {
                await SwiftDataMigration.runIfNeeded(modelContainer: LingoDexApp.modelContainer)
                await viewModel.loadFullCaptures()
            }
        }
    }

    private func mainContent(capturesViewModel: CapturesViewModel) -> some View {
        let tabBarHidden =
            isKeyboardVisible || capturesViewModel.selectedWord != nil
        return ZStack(alignment: .bottom) {
            Group {
                switch viewModel.selectedTab {
                case .captures:
                    CapturesView(deps: deps, appViewModel: viewModel, capturesViewModel: capturesViewModel)
                case .practice:
                    PracticeView(deps: deps, appViewModel: viewModel, viewModel: practiceViewModel)
                case .world:
                    WorldView(deps: deps, viewModel: worldViewModel)
                case .me:
                    MeView(deps: deps, appViewModel: viewModel, viewModel: meViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            MainTabBar(
                selected: viewModel.selectedTab,
                onSelect: { tab in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.selectedTab = tab
                    }
                },
                onCenterCapture: {
                    #if targetEnvironment(simulator)
                    isShowingPhotoPicker = true
                    #else
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        isShowingCaptureFlow = true
                    } else {
                        isShowingPhotoPicker = true
                    }
                    #endif
                }
            )
            // Keep only the custom tab bar pinned so keyboard overlays it.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .opacity(tabBarHidden ? 0 : 1)
            .offset(y: tabBarHidden ? 120 : 0)
            .allowsHitTesting(!tabBarHidden)
            .animation(.easeOut(duration: 0.2), value: tabBarHidden)
            .padding(.bottom, 14)
        }
        .background(DesignTokens.colors.background.ignoresSafeArea())
        .tint(DesignTokens.colors.primary)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: isShowingCaptureFlow) { _, visible in
            if visible {
                if let consumed = deps.cameraWarmup.consumePreWarmedSession() {
                    preWarmedCameraSession = (consumed.session, consumed.photoOutput)
                } else {
                    preWarmedCameraSession = nil
                }
            } else {
                preWarmedCameraSession = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCaptureFlow) {
            CaptureFlowView(
                isPresented: $isShowingCaptureFlow,
                deps: deps,
                viewModel: capturesViewModel,
                preWarmedSession: preWarmedCameraSession?.session,
                preWarmedPhotoOutput: preWarmedCameraSession?.photoOutput
            )
        }
        .sheet(isPresented: $isShowingPhotoPicker) {
            CapturePhotoPicker(
                isPresented: $isShowingPhotoPicker,
                onImagePicked: { image in
                    isShowingPhotoPicker = false
                    isShowingCaptureFlow = true
                    let info = CapturedImageInfo(image: image, previewSize: nil)
                    Task { await capturesViewModel.processCapturedImage(info) }
                }
            )
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let now = Date()
            guard !isActiveRefreshInFlight, now.timeIntervalSince(lastActiveRefreshAt) > 2 else { return }
            isActiveRefreshInFlight = true
            lastActiveRefreshAt = now
            Task {
                await capturesViewModel.load()
                await deps.recognitionSync.syncIfNeeded()
                await MainActor.run { isActiveRefreshInFlight = false }
            }
        }
        .onChange(of: viewModel.selectedTab) { _, tab in
            if tab == .captures {
                warmUpCapturesServices()
            }
        }
        .onAppear {
            guard !didRunStartupWarmups else { return }
            didRunStartupWarmups = true
            if viewModel.selectedTab == .captures {
                warmUpCapturesServices()
            }
        }
    }

    private var loadingState: some View {
        ZStack {
            DesignTokens.colors.background.ignoresSafeArea()
            ProgressView()
        }
    }

    /// Schedules SubjectLift + Gemini warm-up after 1.5s when on Captures tab.
    private func warmUpCapturesServices() {
        deps.cameraWarmup.warmUpIfNeeded()
        recognitionWarmUpTask?.cancel()
        recognitionWarmUpTask = Task(priority: .utility) {
            await scheduleRecognitionWarmUp()
        }
    }

    private func scheduleRecognitionWarmUp() async {
        try? await Task.sleep(for: .seconds(3.0))
        guard !Task.isCancelled else { return }
        await deps.geminiRecognition.warmUp()
    }
}

#Preview {
    ContentView()
}
