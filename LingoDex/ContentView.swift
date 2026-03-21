//
//  ContentView.swift
//  LingoDex
//
//  Created by Jia Yun Zhao on 2026-03-19.
//

import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        MainTabContainer()
    }
}

private struct MainTabContainer: View {
    @State private var viewModel = AppViewModel()
    private let deps = Dependencies.live
    @State private var capturesViewModel = CapturesViewModel(deps: Dependencies.live)
    @State private var isShowingCaptureFlow = false
    @State private var isShowingPhotoPicker = false

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
            .padding(.bottom, 14)
        }
        .background(DesignTokens.colors.background.ignoresSafeArea())
        .tint(DesignTokens.colors.primary)
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
                sourceType: .photoLibrary,
                onImagePicked: { image in
                    Task { @MainActor in
                        await capturesViewModel.processCapturedImage(image)
                        if capturesViewModel.captureFlowPhase == .result {
                            isShowingPhotoPicker = false
                            isShowingCaptureFlow = true
                        }
                    }
                }
            )
        }
        .task {
            if viewModel.authUser == nil {
                viewModel.authUser = deps.auth.currentUser
            }
        }
    }
}

#Preview {
    ContentView()
}
