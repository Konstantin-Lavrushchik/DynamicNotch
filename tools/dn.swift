// Sends a debug command to a DynamicNotch started with DYNAMICNOTCH_DEBUG=1.
// Usage: swift tools/dn.swift timer:90
import Foundation
let cmd = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(Notification.Name("app.dynamicnotch.debug"),
                                                             object: cmd, userInfo: nil, deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
