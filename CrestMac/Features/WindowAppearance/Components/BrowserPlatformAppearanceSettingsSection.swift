import SwiftUI

/// The shared Window group, plus the window choices only the desktop has:
/// light or dark, how far dark dims Space colors, Space page motion, the
/// sidebar hover area, how long it waits and how long the sidebar slides,
/// whether it stays live over a page in full screen, and the border pages take
/// in a full-screen window.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue

    var body: some View {
        let mode = CrestSettingValue($appearance.mode, default: BrowserLookAndFeelDefaults.appearanceMode)
        let dimming = CrestSettingValue(
            $appearance.darkSpaceDimming, default: BrowserLookAndFeelDefaults.darkSpaceDimming)

        let motion = CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)

        let revealWidth = CrestSettingValue(
            $appearance.sidebarRevealWidth, default: SidebarRevealWidthPreference.defaultValue)
        let revealDelay = CrestSettingValue(
            $appearance.sidebarRevealDelay, default: SidebarRevealDelayPreference.defaultValue)
        let slide = CrestSettingValue($appearance.sidebarSlideDuration, default: BrowserSidebarSlide.defaultValue)
        let fullscreenReveal = CrestSettingValue(
            $revealsSidebarInFullscreen, default: SidebarFullscreenRevealPreference.defaultValue)
        let fullScreenMatchesBorder = CrestSettingValue(
            $appearance.fullScreenMatchesWindowBorder, default: BrowserLookAndFeelDefaults.fullScreenMatchesWindowBorder
        )
        let fullScreenBorder = CrestSettingValue(
            $appearance.fullScreenBorderWidth, default: BrowserLookAndFeelDefaults.fullScreenBorderWidth)

        return BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [
                (.appearanceMode, mode.resettable("Appearance")),
                (.darkSpaceDimming, dimming.resettable("Dim Space colors in dark")),
                (.spacePageMotion, motion.resettable("Animate pages when switching Spaces")),
                (.sidebarRevealWidth, revealWidth.resettable("Sidebar hover area")),
                (.sidebarRevealDelay, revealDelay.resettable("Sidebar hover delay")),
                (.sidebarSlideDuration, slide.resettable("Sidebar slide time")),
                (.fullScreenSidebarReveal, fullscreenReveal.resettable("Show sidebar on hover in full screen")),
                (.fullScreenMatchesBorder, fullScreenMatchesBorder.resettable("Same border in full screen")),
                (.fullScreenBorder, fullScreenBorder.resettable("Full-screen border")),
            ]
        ) {
            CrestSettingRow("Appearance", setting: mode.resettable("Appearance")) {
                Picker("Appearance", selection: mode.binding) {
                    ForEach(BrowserAppearanceMode.all, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("appearance-mode")
            }
            .browserAppearanceSetting(.appearanceMode)

            CrestSettingSlider(
                "Dim Space colors in dark",
                value: dimming,
                readout: .percent(zero: "Off", full: "Full"),
                identifier: "dark-space-dimming"
            )
            .browserAppearanceSetting(.darkSpaceDimming)

            BrowserSpacePageMotionRow(motion: motion)

            CrestSettingSlider(
                "Sidebar hover area",
                value: revealWidth,
                range: SidebarRevealWidthPreference.range,
                readout: .points,
                identifier: "sidebar-reveal-width",
                onEditingChanged: { _ in SidebarRevealWidthPreview.shared.adjusted() }
            )
            .onChange(of: appearance.sidebarRevealWidth) { SidebarRevealWidthPreview.shared.adjusted() }
            .browserAppearanceSetting(.sidebarRevealWidth)

            CrestSettingSlider(
                "Sidebar hover delay",
                value: revealDelay,
                range: SidebarRevealDelayPreference.range,
                readout: .milliseconds(zero: "Instant"),
                identifier: "sidebar-reveal-delay"
            )
            .browserAppearanceSetting(.sidebarRevealDelay)

            CrestSettingSlider(
                "Sidebar slide time",
                value: slide,
                range: BrowserSidebarSlide.range,
                readout: .milliseconds(zero: "Snap"),
                identifier: "sidebar-slide-time"
            )
            .browserAppearanceSetting(.sidebarSlideDuration)

            CrestSettingRow(
                "Show sidebar on hover in full screen",
                setting: fullscreenReveal.resettable("Show sidebar on hover in full screen")
            ) {
                Toggle("Show sidebar on hover in full screen", isOn: fullscreenReveal.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("sidebar-fullscreen-reveal")
            }
            .browserAppearanceSetting(.fullScreenSidebarReveal)

            CrestSettingRow(
                "Same border in full screen",
                setting: fullScreenMatchesBorder.resettable("Same border in full screen")
            ) {
                Toggle("Same border in full screen", isOn: fullScreenMatchesBorder.binding)
                    .labelsHidden()
                    .accessibilityIdentifier("fullscreen-matches-window-border")
            }
            .browserAppearanceSetting(.fullScreenMatchesBorder)

            CrestSettingSlider(
                "Full-screen border",
                value: fullScreenBorder,
                range: BrowserChromeAppearance.borderWidthRange,
                readout: .points(zero: "Borderless"),
                identifier: "fullscreen-border-width"
            )
            .disabled(appearance.fullScreenMatchesWindowBorder)
            .browserAppearanceSetting(.fullScreenBorder)
        }
    }
}
