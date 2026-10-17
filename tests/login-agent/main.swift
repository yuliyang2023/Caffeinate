import Foundation

// Test only in a temporary folder, never the user's login-item settings.
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let appURL = root.appendingPathComponent("Applications/Caffeinate & Coffee.app")
let agent = LoginLaunchAgent(directory: root.appendingPathComponent("LaunchAgents"),
                            appURL: appURL, label: "test.caffeinate.startup")
assert(!agent.isEnabled)
try agent.setEnabled(false)
try agent.setEnabled(true)
assert(agent.isEnabled)
let data = try Data(contentsOf: agent.url)
let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
assert(plist["Label"] as? String == "test.caffeinate.startup")
assert(plist["ProgramArguments"] as? [String] == ["/usr/bin/open", "-g", appURL.path])
assert(plist["RunAtLoad"] as? Bool == true)
assert(plist["KeepAlive"] == nil)
try agent.setEnabled(true)
try agent.setEnabled(false)
assert(!agent.isEnabled)
try agent.setEnabled(false)

let file = root.appendingPathComponent("not-a-directory")
try Data().write(to: file)
let invalid = LoginLaunchAgent(directory: file, appURL: appURL, label: "test")
var failed = false
do { try invalid.setEnabled(true) } catch { failed = true }
assert(failed)
print("Login LaunchAgent checks passed")
