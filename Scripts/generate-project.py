#!/usr/bin/env python3
"""Generate a dependency-free Xcode project with explicit, auditable file references."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent.parent
ident=lambda value:hashlib.sha256(value.encode()).hexdigest()[:24].upper()
q=lambda value:json.dumps(str(value))
objects=[]
def obj(key,body):
 objects.append(f'\t\t{ident(key)} = {{ {body} }};')
files=[]
for f in sorted((ROOT/'App').rglob('*')):
 if f.is_dir() and f.suffix=='.xcassets':files.append(f)
 elif f.is_file() and not any(x.suffix=='.xcassets' for x in f.parents):files.append(f)
sources=[];resources=[];refs=[]
for f in files:
 rel=f.relative_to(ROOT).as_posix();key='file:'+rel;ref=ident(key);refs.append(ref)
 kind={'.swift':'sourcecode.swift','.png':'image.png','.otf':'file','.ttf':'file','.xcassets':'folder.assetcatalog'}.get(f.suffix,'text')
 obj(key,f'isa = PBXFileReference; lastKnownFileType = {q(kind)}; path = {q(rel)}; sourceTree = "<group>";')
 build='build:'+rel;obj(build,f'isa = PBXBuildFile; fileRef = {ref};')
 (sources if f.suffix=='.swift' else resources).append(ident(build))
obj('info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Configuration/Info.plist; sourceTree = "<group>";')
obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WHOOP.app; sourceTree = BUILT_PRODUCTS_DIR;')
arr=lambda xs:'('+','.join(xs)+(',' if xs else '')+')'
obj('appgroup',f'isa = PBXGroup; children = {arr(refs)}; name = Application; sourceTree = "<group>";')
obj('productsgroup',f'isa = PBXGroup; children = ({ident("product")},{ident("widgetproduct")},); name = Products; sourceTree = "<group>";')
obj('maingroup',f'isa = PBXGroup; children = ({ident("appgroup")},{ident("info")},{ident("widgetgroup")},{ident("productsgroup")},); sourceTree = "<group>";')
obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {arr(sources)}; runOnlyForDeploymentPostprocessing = 0;')
obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {arr(resources)}; runOnlyForDeploymentPostprocessing = 0;')
obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
obj('packageproduct',f'isa = XCSwiftPackageProductDependency; package = {ident("package")}; productName = WHOOPCore;')
obj('packagebuild',f'isa = PBXBuildFile; productRef = {ident("packageproduct")};')
obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ident("packagebuild")},); runOnlyForDeploymentPostprocessing = 0;')
obj('widgetfile', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LiveActivityWidget/WorkoutLiveWidget.swift; sourceTree = "<group>";')
obj('widgetinfo', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = LiveActivityWidget/Info.plist; sourceTree = "<group>";')
obj('widgetproduct', 'isa = PBXFileReference; explicitFileType = wrapper.app-extension; includeInIndex = 0; path = WorkoutLive.appex; sourceTree = BUILT_PRODUCTS_DIR;')
obj('widgetgroup', f'isa = PBXGroup; children = ({ident("widgetfile")},{ident("widgetinfo")},); name = LiveActivityWidget; sourceTree = "<group>";')
obj('widgetbuildsource', f'isa = PBXBuildFile; fileRef = {ident("widgetfile")};')
obj('widgetsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ident("widgetbuildsource")},); runOnlyForDeploymentPostprocessing = 0;')
obj('widgetresources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('widgetpackageproduct', f'isa = XCSwiftPackageProductDependency; package = {ident("package")}; productName = WHOOPCore;')
obj('widgetpackagebuild', f'isa = PBXBuildFile; productRef = {ident("widgetpackageproduct")};')
obj('widgetframeworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ident("widgetpackagebuild")},); runOnlyForDeploymentPostprocessing = 0;')
obj('widgetembedbuild', f'isa = PBXBuildFile; fileRef = {ident("widgetproduct")}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy,); }};')
obj('embedextensions', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({ident("widgetembedbuild")},); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
obj('widgetproxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("widgettarget")}; remoteInfo = WorkoutLive;')
obj('widgetdependency', f'isa = PBXTargetDependency; target = {ident("widgettarget")}; targetProxy = {ident("widgetproxy")};')
projectsettings='CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;'
targetsettings='ASSETCATALOG_COMPILER_APPICON_NAME = WhoopAppIcon; CODE_SIGN_ENTITLEMENTS = Configuration/WHOOP.entitlements; CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; DEVELOPMENT_TEAM = ""; ENABLE_PREVIEWS = YES; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = Configuration/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 17.0; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)","@executable_path/Frameworks",); MARKETING_VERSION = 0.1.0; APP_BUNDLE_IDENTIFIER = local.whoop.reconstruction; PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_IDENTIFIER)"; PRODUCT_NAME = "$(TARGET_NAME)"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = 1;'
widgetsettings='APPLICATION_EXTENSION_API_ONLY = YES; CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = ""; APP_BUNDLE_IDENTIFIER = local.whoop.reconstruction; CURRENT_PROJECT_VERSION = 1; DEVELOPMENT_TEAM = ""; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = LiveActivityWidget/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 17.0; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)","@executable_path/Frameworks","@executable_path/../../Frameworks",); MARKETING_VERSION = 0.1.0; PRODUCT_BUNDLE_IDENTIFIER = "$(APP_BUNDLE_IDENTIFIER).WorkoutLive"; PRODUCT_NAME = WorkoutLive; SKIP_INSTALL = YES; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = 1;'
for scope,settings in [('project',projectsettings),('target',targetsettings),('widget',widgetsettings)]:
 for name in ['Debug','Release']:
  extra='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule;'
  obj(scope+name,f'isa = XCBuildConfiguration; buildSettings = {{ {settings} {extra} }}; name = {name};')
 obj(scope+'configs',f'isa = XCConfigurationList; buildConfigurations = ({ident(scope+"Debug")},{ident(scope+"Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {ident("targetconfigs")}; buildPhases = ({ident("sources")},{ident("frameworks")},{ident("resources")},{ident("embedextensions")},); buildRules = (); dependencies = ({ident("widgetdependency")},); name = WHOOP; packageProductDependencies = ({ident("packageproduct")},); productName = WHOOP; productReference = {ident("product")}; productType = "com.apple.product-type.application";')
obj('widgettarget', f'isa = PBXNativeTarget; buildConfigurationList = {ident("widgetconfigs")}; buildPhases = ({ident("widgetsources")},{ident("widgetframeworks")},{ident("widgetresources")},); buildRules = (); dependencies = (); name = WorkoutLive; packageProductDependencies = ({ident("widgetpackageproduct")},); productName = WorkoutLive; productReference = {ident("widgetproduct")}; productType = "com.apple.product-type.app-extension";')
obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {ident("target")} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ "com.apple.HealthKit" = {{ enabled = 1; }}; }}; }}; }}; }}; buildConfigurationList = {ident("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,); mainGroup = {ident("maingroup")}; packageReferences = ({ident("package")},); productRefGroup = {ident("productsgroup")}; projectDirPath = ""; projectRoot = ""; targets = ({ident("target")},{ident("widgettarget")},);')
project=ROOT/'WHOOP.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+ident('project')+';\n}\n')
scheme=ET.Element('Scheme',LastUpgradeVersion='1600',version='1.3')
build=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES');entries=ET.SubElement(build,'BuildActionEntries');entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES')
def buildable(parent):ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=ident('target'),BuildableName='WHOOP.app',BlueprintName='WHOOP',ReferencedContainer='container:WHOOP.xcodeproj')
buildable(entry)
ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES')
launch=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES');buildable(ET.SubElement(launch,'BuildableProductRunnable',runnableDebuggingMode='0'))
profile=ET.SubElement(scheme,'ProfileAction',buildConfiguration='Release',shouldUseLaunchSchemeArgsEnv='YES',savedToolIdentifier='',useCustomWorkingDirectory='NO',debugDocumentVersioning='YES');buildable(ET.SubElement(profile,'BuildableProductRunnable',runnableDebuggingMode='0'))
ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug');ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
schemedir=project/'xcshareddata/xcschemes';schemedir.mkdir(parents=True,exist_ok=True);ET.indent(scheme)
(schemedir/'WHOOP.xcscheme').write_bytes(ET.tostring(scheme,encoding='utf-8',xml_declaration=True))
print(f'Generated project with {len(sources)} Swift files, {len(resources)} resource entries, the WorkoutLive extension and local WHOOPCore package.')
