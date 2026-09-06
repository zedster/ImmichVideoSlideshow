//
//  ImmichVideoChannelTests.swift
//  ImmichVideoChannelTests
//
//  Created by Seb B on 08/03/2026.
//

import AVFoundation
import Foundation
import Testing
@testable import HomeVideoChannel

struct ImmichVideoChannelTests {

    @Test func defaultConfigurationEnforcesTenSecondMinimum() {
        let config = AppConfig()

        #expect(config.minDuration == 10)
        #expect(config.includesDuration(10))
        #expect(!config.includesDuration(9.999))
    }

    @Test func configurationWithoutMinimumDurationUsesTenSecondDefault() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))

        #expect(config.minDuration == 10)
    }

    @Test func timeChannelsPersistAndOlderConfigurationsDefaultToAllDates() throws {
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8)).timeChannel == nil)
        for channel in TimeChannel.allCases {
            var config = AppConfig()
            config.timeChannel = channel
            let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
            #expect(decoded.timeChannel == channel)
        }
    }

    @Test func rollingPeriodsIncludeBoundariesAndExcludeFutureDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)))
        let starts: [(TimeChannel, String)] = [(.lastMonth, "2026-02-28"), (.lastThreeMonths, "2025-12-31"), (.lastYear, "2025-03-31"), (.lastFiveYears, "2021-03-31")]
        for (channel, start) in starts {
            #expect(channel.dateBounds(now: now, calendar: calendar)?.start == start)
            #expect(channel.includes(start, now: now, calendar: calendar))
            #expect(channel.includes("2026-03-31T23:59:59Z", now: now, calendar: calendar))
            #expect(!channel.includes("2026-04-01", now: now, calendar: calendar))
            #expect(!channel.includes("2020-01-01", now: now, calendar: calendar))
            #expect(!channel.includes("", now: now, calendar: calendar))
        }
    }

    @Test func seasonsCoverEveryMonthAcrossYears() {
        for year in [2000, 2026] {
            for month in 1...12 {
                let date = String(format: "%04d-%02d-15T12:00:00Z", year, month)
                let matches = [TimeChannel.winter, .spring, .summer, .autumn].filter { $0.includes(date) }
                #expect(matches.count == 1)
                #expect(matches.first?.months.contains(month) == true)
            }
        }
        #expect(TimeChannel.winter.includes("2025-12-31"))
        #expect(TimeChannel.winter.includes("2026-01-01"))
        #expect(!TimeChannel.winter.includes("2026-03-01"))
    }

    @Test func hemisphereDefaultsAndPersistence() throws {
        #expect(AppConfig().seasonHemisphere == .northern)
        #expect(try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8)).seasonHemisphere == .northern)
        var config = AppConfig()
        config.seasonHemisphere = .southern
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.seasonHemisphere == .southern)
    }

    @Test func southernSeasonsSwapMonthsAndLeaveRollingPeriodsUnchanged() {
        #expect(TimeChannel.summer.months(in: .southern) == [12, 1, 2])
        #expect(TimeChannel.autumn.months(in: .southern) == [3, 4, 5])
        #expect(TimeChannel.winter.months(in: .southern) == [6, 7, 8])
        #expect(TimeChannel.spring.months(in: .southern) == [9, 10, 11])
        for month in 1...12 {
            let date = String(format: "2025-%02d-15", month)
            let matches = [TimeChannel.winter, .spring, .summer, .autumn].filter {
                $0.includes(date, hemisphere: .southern)
            }
            #expect(matches.count == 1)
            #expect(TimeChannel.summer.includes(date, hemisphere: .southern) == TimeChannel.winter.includes(date))
            #expect(TimeChannel.lastYear.includes(date, hemisphere: .southern) == TimeChannel.lastYear.includes(date))
        }
    }

}


struct PlaybackRecoveryTests {
    @Test @MainActor func readinessTimeoutFinishesForAnItemThatNeverLoads() async {
        let coordinator = ChannelCoordinator(configStore: ConfigStore())
        // An unattached item stays unknown; no server or media fixture is needed.
        let item = AVPlayerItem(asset: AVMutableComposition())
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await coordinator.waitUntilReadyToPlay(item: item, timeoutSeconds: 0.1)
            Issue.record("An unknown item must time out")
        } catch {
            #expect(!(error is CancellationError))
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }

    @Test @MainActor func readinessWaitRespondsToCancellation() async throws {
        let coordinator = ChannelCoordinator(configStore: ConfigStore())
        let item = AVPlayerItem(asset: AVMutableComposition())
        let task = Task {
            try await coordinator.waitUntilReadyToPlay(item: item, timeoutSeconds: 60)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled readiness wait must throw")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }

    @Test func watchdogDetectsFrozenPlaybackAndResetsWhenProgressResumes() {
        var watchdog = PlaybackProgressWatchdog()
        watchdog.reset(position: 5, now: 100)
        let observation1 = !watchdog.isStalled(position: 5, now: 119)
        #expect(observation1)
        let observation2 = watchdog.isStalled(position: 5, now: 120)
        #expect(observation2)
        let observation3 = !watchdog.isStalled(position: 6, now: 121)
        #expect(observation3)
        let observation4 = !watchdog.isStalled(position: 6, now: 140)
        #expect(observation4)
        let observation5 = watchdog.isStalled(position: 6, now: 141)
        #expect(observation5)
        watchdog.reset(position: 6, now: 200) // Resume after a deliberate pause.
        let observation6 = !watchdog.isStalled(position: 6, now: 201)
        #expect(observation6)
    }

    @Test func watchdogHandlesUnknownTimesAndSeekingBackwards() {
        var watchdog = PlaybackProgressWatchdog()
        watchdog.reset(position: .nan, now: 10)
        let observation7 = watchdog.isStalled(position: .nan, now: 30)
        #expect(observation7)
        let observation8 = !watchdog.isStalled(position: 50, now: 31)
        #expect(observation8)
        let observation9 = !watchdog.isStalled(position: 10, now: 50)
        #expect(observation9)
    }

    @Test @MainActor func foregroundRecreatesPlayersAndPreservesManualPause() async {
        let configStore = ConfigStore()
        configStore.config = AppConfig()
        configStore.config.immichURL = "http://127.0.0.1:1"
        configStore.config.apiKey = "test"
        let coordinator = ChannelCoordinator(configStore: configStore)
        coordinator.start()
        let firstPlayer = coordinator.playerA
        coordinator.togglePlayPause()
        coordinator.handleScenePhase(.background)
        #expect(coordinator.isPlaybackPaused)
        #expect(firstPlayer.currentItem == nil)
        coordinator.restart() // Settings changes while suspended must not start playback.
        #expect(coordinator.playerA === firstPlayer)
        coordinator.togglePlayPause()
        coordinator.handleScenePhase(.active)
        #expect(coordinator.playerA !== firstPlayer)
        #expect(coordinator.isPlaybackPaused)
        let resumedPlayer = coordinator.playerA
        coordinator.handleScenePhase(.active)
        #expect(coordinator.playerA === resumedPlayer)
        coordinator.stop()
        // All queued startup work belongs to stopped generations.
        for _ in 0..<10 { await Task.yield() }
        #expect(coordinator.playerA.currentItem == nil)
        #expect(coordinator.fallbackMessage.isEmpty)
        #expect(!coordinator.shouldOpenSetup)
    }
}


private final class SuspendedPlaybackRequest: URLProtocol {
    private static let lock = NSLock()
    private static var didStart = false
    private static var didCancel = false

    static var state: (started: Bool, cancelled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (didStart, didCancel)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.didStart = true
        Self.lock.unlock()
        // Leave the request pending until the coordinator cancels its task.
    }
    override func stopLoading() {
        Self.lock.lock()
        Self.didCancel = true
        Self.lock.unlock()
    }
}

extension PlaybackRecoveryTests {
    @Test @MainActor func backgroundCancelsAnInFlightBootstrapWithoutReportingFailure() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [SuspendedPlaybackRequest.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let configStore = ConfigStore()
        configStore.config = AppConfig()
        configStore.config.immichURL = "https://playback.test"
        configStore.config.apiKey = "test"
        configStore.config.useSQLiteCache = false
        let coordinator = ChannelCoordinator(configStore: configStore, client: ImmichAPIClient(session: session))
        coordinator.start()
        defer { coordinator.stop() }
        for _ in 0..<100 where !SuspendedPlaybackRequest.state.started {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(SuspendedPlaybackRequest.state.started)
        coordinator.handleScenePhase(.background)
        for _ in 0..<100 where !SuspendedPlaybackRequest.state.cancelled {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(SuspendedPlaybackRequest.state.cancelled)
        for _ in 0..<10 { await Task.yield() }
        #expect(coordinator.fallbackMessage.isEmpty)
        #expect(!coordinator.shouldOpenSetup)
        #expect(coordinator.playerA.currentItem == nil)
    }
}
