//
//  ConfigHandler.swift
//  Caffeinate
//
//  Created by Lennard on 26.10.22.
//

import Foundation
import Combine
import ServiceManagement
import AppKit
import Security

/// Unsigned builds cannot rely on SMAppService's signing identity. A user
/// LaunchAgent opens the app once at the next login, without root privileges.
struct LoginLaunchAgent {
    let directory: URL
    let appURL: URL
    let label: String

    var url: URL { directory.appendingPathComponent(label + ".plist") }

    var isEnabled: Bool { FileManager.default.fileExists(atPath: url.path) }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-g", appURL.path],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml, options: 0)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: url)
        }
    }
}

class ConfigHandler :ObservableObject {
    
    // ~/Library/Containers/com.Lennard.SettingsSwitfUI/Data/Library/"Application Support"/Caffeinate
    static let CONF_FILE = URL(fileURLWithPath: "\(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path)/Caffeinate/Caffeinate.json")
    @Published var conf :ConfigData
    @Published var curretnTab :Int
    var macOS13 :Bool
    private var oldConf :ConfigData! // necessary because removeDuplicates(by: ) does not work
    private var configSink :Cancellable!

    private var loginAgent: LoginLaunchAgent {
        LoginLaunchAgent(
            directory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            appURL: Bundle.main.bundleURL,
            label: (Bundle.main.bundleIdentifier ?? "com.Lennard.Caffeinate") + ".startup")
    }

    private var hasSigningTeam: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code = code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode = staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let values = information as? [String: Any] else { return false }
        return values[kSecCodeInfoTeamIdentifier as String] as? String != nil
    }
    
    init() {
        if #available(macOS 13.0, *) {
            macOS13 = true
        } else {
            macOS13 = false
        }
        curretnTab = 1
        conf = ConfigHandler.readCfg(from: ConfigHandler.CONF_FILE) ?? ConfigData()
        updateAtLogin()
        oldConf = ConfigData(copy: conf)
        configSink = $conf.sink(receiveValue: { conf in
            if conf == self.oldConf {
                return
            }
            ConfigHandler.writeCfg(conf, to: ConfigHandler.CONF_FILE)
            self.oldConf = ConfigData(copy: conf)
        })
    }
    
    private func updateAtLogin() {
        if #available(macOS 13.0, *) {
            conf.atLogin = loginAgent.isEnabled || SMAppService.mainApp.status == .enabled
        }
    }

    /// Mutates the config and reassigns it so the @Published sink persists the
    /// change. ConfigData is a class, so an in-place mutation alone would not
    /// trigger publication.
    func mutateConfig(_ change: (ConfigData) -> Void) {
        let updated = ConfigData(copy: conf)
        change(updated)
        conf = updated
    }

    /// Outcome of trying to change the login-item registration.
    enum LoginItemResult {
        case ok(enabled: Bool)   // registration reflects the request
        case requiresApproval    // the user must enable it in System Settings
        case failed(Error)       // the register/unregister call threw
        case unsupported         // macOS < 13
    }

    /// Attempts to register/unregister the login item, then persists the config
    /// to whatever the system actually reports — so the checkmark never lies.
    @discardableResult
    func setAtLogin(_ desired: Bool) -> LoginItemResult {
        guard #available(macOS 13.0, *) else {
            mutateConfig { $0.atLogin = false }
            return .unsupported
        }
        // Keep using an existing LaunchAgent even if a later build is signed,
        // so toggling the setting always removes the registration it created.
        if !hasSigningTeam || loginAgent.isEnabled {
            do {
                // Remove any old SMAppService registration to avoid duplicates.
                if SMAppService.mainApp.status == .enabled ||
                    SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
                try loginAgent.setEnabled(desired)
                mutateConfig { $0.atLogin = loginAgent.isEnabled }
                return .ok(enabled: conf.atLogin)
            } catch {
                let enabled = loginAgent.isEnabled || SMAppService.mainApp.status == .enabled
                mutateConfig { $0.atLogin = enabled }
                return .failed(error)
            }
        }
        var caughtError: Error?
        do {
            if desired {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            caughtError = error
        }
        // Reflect the real, post-call status rather than the requested value.
        let status = SMAppService.mainApp.status
        mutateConfig { $0.atLogin = (status == .enabled) }
        if let caughtError {
            return .failed(caughtError)
        }
        if status == .requiresApproval {
            return .requiresApproval
        }
        return .ok(enabled: status == .enabled)
    }
    
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
        
    static func readCfg(from file: URL) -> ConfigData? {
        if let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            return try? decoder.decode(ConfigData.self, from: data)
        }
        return nil
    }

    static func writeCfg(_ conf: ConfigData, to file: URL) {
        if let jsonData = try? JSONEncoder().encode(conf) {
            try? FileManager.default.createDirectory(atPath: file.deletingLastPathComponent().path, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: nil)
            try? jsonData.write(to: file)
        }
    }
}
