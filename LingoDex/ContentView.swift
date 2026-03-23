//
//  ContentView.swift
//  LingoDex
//
//  Created by Jia Yun Zhao on 2026-03-19.
//

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
    @State private var capturesViewModel = CapturesViewModel(deps: Dependencies.live)
    @State private var isShowingCaptureFlow = false
    @State private var isShowingPhotoPicker = false
    @State private var isKeyboardVisible = false

    var body: some View {
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .fullScreenCover(isPresented: $isShowingCaptureFlow) {
            CaptureFlowView(
                isPresented: $isShowingCaptureFlow,
                deps: deps,
                viewModel: capturesViewModel
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
            if phase == .active {
                Task { await capturesViewModel.load(); await deps.recognitionSync.syncIfNeeded() }
            }
        }
        .task {
            // Warm up Photos framework so the photo picker sheet opens faster
            try? await Task.sleep(for: .seconds(0.8))
            _ = PHPickerConfiguration(photoLibrary: .shared())
            // Pre-warm TTS so first speaker tap works immediately (iOS loads voices on-demand)
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(1))
                try? await deps.tts.speak(" ", language: .currentLearning)
            }
        }
    }
}

#Preview {
    ContentView()
}
