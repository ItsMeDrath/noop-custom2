import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let projectURL = root.appendingPathComponent("WHOOP.xcodeproj/project.pbxproj")
var format = PropertyListSerialization.PropertyListFormat.openStep
let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: projectURL), options: [], format: &format)
guard let project = value as? [String: Any], let objects = project["objects"] as? [String: [String: Any]],
      let rootID = project["rootObject"] as? String, objects[rootID]?["isa"] as? String == "PBXProject" else {
    fatalError("Invalid Xcode project root")
}
var sources = Set<String>(), resourceNames = Set<String>()
for (id, object) in objects {
    for key in ["fileRef", "productRef", "productReference", "buildConfigurationList", "mainGroup", "productRefGroup", "package", "target", "targetProxy", "containerPortal", "remoteGlobalIDString"] {
        if let ref = object[key] as? String { precondition(objects[ref] != nil, "Dangling \(key) in \(id)") }
    }
    for key in ["children", "files", "buildPhases", "buildConfigurations", "targets", "packageReferences", "packageProductDependencies"] {
        for ref in object[key] as? [String] ?? [] { precondition(objects[ref] != nil, "Dangling \(key) in \(id)") }
    }
    if object["isa"] as? String == "PBXFileReference", object["sourceTree"] as? String == "<group>", let path = object["path"] as? String {
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "Missing \(path)")
        if path.hasPrefix("App/"), path.hasSuffix(".swift") { sources.insert(path) }
        else { resourceNames.insert(URL(fileURLWithPath: path).lastPathComponent) }
    }
}
let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("App"), includingPropertiesForKeys: nil)!
let actualSources = Set(enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map { String($0.path.dropFirst(root.path.count + 1)) })
precondition(sources == actualSources, "App Swift files omitted from project")
let infoURL = root.appendingPathComponent("Configuration/Info.plist")
let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
precondition(["PULSE", "WHOOP"].contains(info["CFBundleDisplayName"] as? String ?? ""))
precondition(info["NSBluetoothAlwaysUsageDescription"] is String)
for font in info["UIAppFonts"] as? [String] ?? [] { precondition(resourceNames.contains(font), "Unbundled font \(font)") }
let widgets = objects.values.filter { $0["productType"] as? String == "com.apple.product-type.app-extension" }
precondition(widgets.count == 1, "Missing workout widget extension")
let apps = objects.values.filter { $0["productType"] as? String == "com.apple.product-type.application" }
precondition(apps.count == 1)
let widgetID = objects.first { $0.value["productType"] as? String == "com.apple.product-type.app-extension" }!.key
let dependencyIDs = apps[0]["dependencies"] as? [String] ?? []
precondition(dependencyIDs.contains { objects[$0]?["target"] as? String == widgetID }, "App does not build its widget")
let embed = objects.values.first { $0["isa"] as? String == "PBXCopyFilesBuildPhase" && $0["dstSubfolderSpec"] as? String == "13" }
precondition(embed != nil, "Missing extension embed phase")
precondition(info["NSSupportsLiveActivities"] as? Bool == true)
print("WorkoutLive extension dependency and embedding structure passed.")
print("Xcode project structural validation passed: \(sources.count) app sources; all object references, resource paths and registered fonts exist.")
print("This is not an Apple SDK typecheck or an iOS build.")
