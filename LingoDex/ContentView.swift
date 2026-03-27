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
import PhotosUI

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
    @State private var isShowingCaptureFlow = false
    @State private var preWarmedCameraSession: (session: AVCaptureSession, photoOutput: AVCapturePhotoOutput?)?
    @State private var isShowingPhotoPicker = false
    @State private var isKeyboardVisible = false
    @State private var migrationInProgress = false
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
            migrationInProgress = true

            Task(priority: .utility) {
                await SwiftDataMigration.runIfNeeded(modelContainer: LingoDexApp.modelContainer)
                await MainActor.run {
                    migrationInProgress = false
                }
                await viewModel.loadFullCaptures()
            }
        }
    }

    private func mainContent(capturesViewModel: CapturesViewModel) -> some View {
        ZStack(alignment: .bottom) {
            Group {
                switch viewModel.selectedTab {
                case .captures:
                    CapturesView(deps: deps, appViewModel: viewModel, capturesViewModel: capturesViewModel)
                case .practice:
                    PracticeView(deps: deps, appViewModel: viewModel)
                case .world:
                    WorldView(deps: deps)
                case .me:
                    MeView(deps: deps, appViewModel: viewModel)
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
            .opacity(isKeyboardVisible ? 0 : 1)
            .offset(y: isKeyboardVisible ? 120 : 0)
            .allowsHitTesting(!isKeyboardVisible)
            .animation(.easeOut(duration: 0.2), value: isKeyboardVisible)
            .padding(.bottom, 14)
        }
        .background(DesignTokens.colors.background.ignoresSafeArea())
        .tint(DesignTokens.colors.primary)
        .overlay(alignment: .top) {
            if migrationInProgress {
                Text("Optimizing library...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.colors.capturesTextSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
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
                    capturesViewModel.captureFlowPhase = .processing
                    capturesViewModel.isProcessingCapture = true
                    capturesViewModel.pendingWord = nil
                    capturesViewModel.pendingExtractedImage = nil
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
        .task {
            // T+0: Touch services so tabs are fast on first visit.
            _ = deps.imageLoader
            _ = deps.captureStore
            // Photos + TTS warm-up (existing)
            try? await Task.sleep(for: .seconds(0.3))
            _ = PHPickerConfiguration(photoLibrary: .shared())
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(0.7))
                try? await deps.tts.speak(" ", language: .currentLearning)
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
        let subjectLift = deps.subjectLift
        let geminiRecognition = deps.geminiRecognition
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        try? await subjectLift.warmUp()
        guard !Task.isCancelled else { return }
        await geminiRecognition.warmUp()
    }
}

#Preview {
    ContentView()
}
