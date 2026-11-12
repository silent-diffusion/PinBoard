//
//  SyncPolicy.swift  —  PinBoard
//
//  The plain rules around an iCloud sync, kept apart from the sync itself so they can be tested
//  on their own:
//  - whether Settings may switch profiles now (an import must finish; a sync never blocks: it is
//    stopped and picks up next time — its result is dropped, the library is saved first);
//  - why a sync stopped, what Settings says about it, and when the next one starts (offline: as
//    soon as the connection is back; iCloud sending nothing: later and later, up to 30 minutes).
//

import Foundation

/// What Settings › Profiles does when a profile is tapped.
enum ProfileSwitchPlan: Equatable, Sendable {
    case switchNow                // nothing is running
    case stopSyncThenSwitch       // a sync is running: it is told to stop, then the switch happens at once
    case waitForImport            // an import is writing into this library: switching waits

    /// `importing`: an import, a share-inbox intake or a folder import is under way (library work).
    /// `syncing`: an iCloud sync (or its quiet download) is under way.
    static func plan(importing: Bool, syncing: Bool) -> ProfileSwitchPlan {
        if importing { return .waitForImport }
        return syncing ? .stopSyncThenSwitch : .switchNow
    }
}

/// Why a sync ended before everything had come.
enum SyncStop: Equatable, Sendable {
    case offline          // the device has no connection
    case noICloud         // not signed in to iCloud, or iCloud Drive is off
    case iCloudQuiet      // connected, but iCloud sent nothing for a while
    case stopTapped       // Stop in Settings
    case profileChanged   // another profile was opened

    /// The line Settings shows under the sync (nil: nothing to say).
    func message(retryMinutes: Int?) -> String? {
        switch self {
        case .offline:
            return "Offline — will sync when you're back online."
        case .noICloud:
            return "iCloud isn't available. Check that this device is signed in to iCloud with iCloud Drive on."
        case .iCloudQuiet:
            guard let retryMinutes else { return "iCloud isn't sending anything right now." }
            return "iCloud isn't sending anything right now. Trying again in \(retryMinutes) minute\(retryMinutes == 1 ? "" : "s")."
        case .stopTapped, .profileChanged:
            return nil
        }
    }
}

/// When the next sync starts after one ended.
enum SyncRetry: Equatable, Sendable {
    case none                     // no automatic retry (Stop, another profile: that one syncs on its own)
    case whenOnline               // as soon as the connection is back
    case after(seconds: Double)   // after a pause

    /// The pause after a sync that ended with pins still to come. `quietRuns`: how many runs in a
    /// row iCloud sent nothing (counting this one): 2, 4, 8, 16, then 30 minutes.
    static func after(_ stop: SyncStop?, quietRuns: Int) -> SyncRetry {
        switch stop {
        case .offline, .noICloud: return .whenOnline
        case .stopTapped, .profileChanged: return .none
        case .iCloudQuiet:
            let minutes = min(30, 2 * (1 << min(max(quietRuns - 1, 0), 4)))
            return .after(seconds: Double(minutes) * 60)
        case nil: return .after(seconds: 120)   // pins still to come (not in iCloud yet)
        }
    }

    /// Whole minutes until the retry (for the message), nil when it doesn't wait for a clock.
    var minutes: Int? {
        if case .after(let seconds) = self { return Int((seconds / 60).rounded()) }
        return nil
    }
}
