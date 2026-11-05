#!/usr/bin/env python3
"""
Writes PinBoard.xcodeproj/project.pbxproj: the app (every Swift file at the top of ../PinBoard,
plus App/), the widget extension (PinBoardWidgets/) and the share extension (PinBoardShare/), both
embedded in the app. Files in ../PinBoard
that aren't the app's own Swift files are left out by name, so run
this again after adding such files there (upload-testflight.sh does, before every upload).

    python3 make-project.py
"""
import hashlib, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.normpath(os.path.join(HERE, "..", "PinBoard"))
# Everything in ../PinBoard that is not a Swift file at its top level stays out of the app.
left_out = []
for root, dirs, files in os.walk(SHARED):
    for name in files:
        rel = os.path.relpath(os.path.join(root, name), SHARED)
        if name.startswith("."):
            continue
        if os.sep in rel or not name.endswith(".swift"):
            left_out.append(rel)
left_out.sort()
def oid(name): return hashlib.md5(name.encode()).hexdigest()[:24].upper()
I = {k: oid(k) for k in """project projConfList projDebug projRelease mainGroup productsGroup
appRef widgetRef gShared gApp gWidgets excShared
appTarget appConfList appDebug appRelease appSources appFrameworks appResources appEmbed embedFile
widgetTarget widgetConfList widgetDebug widgetRelease widgetSources widgetFrameworks widgetResources
proxy dependency shareRef gShare embedShare shareTarget shareConfList shareDebug shareRelease shareSources
shareFrameworks shareResources shareProxy shareDependency""".split()}

common = {
 "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
 "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
 "SWIFT_VERSION": "6.0", "DEVELOPMENT_TEAM": "AW3HL7CANW", "CODE_SIGN_STYLE": "Automatic",
 "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "8", "TARGETED_DEVICE_FAMILY": '"1,2"',
}
debug = dict(common, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "ONLY_ACTIVE_ARCH": "YES", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"', "ENABLE_TESTABILITY": "YES"})
release = dict(common, **{"DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"', "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})
app = {
 "PRODUCT_BUNDLE_IDENTIFIER": "com.silentdiffusion.pinboard2", "PRODUCT_NAME": "PinBoard",
 "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": '"PinBoard-Info.plist"', "INFOPLIST_KEY_CFBundleDisplayName": "PinBoard",
 "INFOPLIST_KEY_LSApplicationCategoryType": '"public.app-category.photography"',
 "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
 "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
 "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": '"UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
 "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"',
 "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "CODE_SIGN_ENTITLEMENTS": "PinBoard.entitlements",
 # The other icons people can pick in Settings › Appearance › App icon (App/AppIcon-*.icon, drawn by
 # AppStore/icon/options.swift; AppIconPicker.swift lists the same names).
 "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES": '"' + " ".join("AppIcon-" + n for n in
    ["FourKinds", "PinnedPhoto", "PushPin", "FoldedNote", "CardStack", "PinP", "TapedSnapshot"]) + '"',
 "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS": "NO",
 "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks"', "ENABLE_PREVIEWS": "NO",
}
widget = {
 "PRODUCT_BUNDLE_IDENTIFIER": "com.silentdiffusion.pinboard2.widgets", "PRODUCT_NAME": "PinBoardWidgets",
 "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": '"PinBoardWidgets-Info.plist"', "INFOPLIST_KEY_CFBundleDisplayName": "PinBoard",
 "SKIP_INSTALL": "YES", "CODE_SIGN_ENTITLEMENTS": "PinBoardWidgets.entitlements", "ENABLE_PREVIEWS": "NO",
 "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',

}
# The share extension ("PinBoard" in the share sheet): it only copies what is shared into the App
# Group's inbox; the app takes it in (ShareShared.swift, ShareInbox.swift).
share = {
 "PRODUCT_BUNDLE_IDENTIFIER": "com.silentdiffusion.pinboard2.share", "PRODUCT_NAME": "PinBoardShare",
 "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": '"PinBoardShare-Info.plist"', "INFOPLIST_KEY_CFBundleDisplayName": "PinBoard",
 "SKIP_INSTALL": "YES", "CODE_SIGN_ENTITLEMENTS": "PinBoardShare.entitlements", "ENABLE_PREVIEWS": "NO",
 "APPLICATION_EXTENSION_API_ONLY": "YES",
 "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
}
def settings(d, indent="\t\t\t\t"):
    return "".join(f"{indent}{k} = {v};\n" for k, v in sorted(d.items()))
def cfg(key, name, d):
    return f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(d)}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n"
def phase(key, isa, name):
    return f"\t\t{I[key]} /* {name} */ = {{\n\t\t\tisa = {isa};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"
out = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{I['embedFile']} /* PinBoardWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['widgetRef']} /* PinBoardWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
		{I['embedShare']} /* PinBoardShare.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {I['shareRef']} /* PinBoardShare.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{I['proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['widgetTarget']};
			remoteInfo = PinBoardWidgets;
		}};
		{I['shareProxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {I['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {I['shareTarget']};
			remoteInfo = PinBoardShare;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{I['appEmbed']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{I['embedFile']} /* PinBoardWidgets.appex in Embed Foundation Extensions */,
				{I['embedShare']} /* PinBoardShare.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{I['appRef']} /* PinBoard.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PinBoard.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['widgetRef']} /* PinBoardWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = PinBoardWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{I['shareRef']} /* PinBoardShare.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = PinBoardShare.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{I['excShared']} /* Exceptions for "PinBoard" folder in "PinBoard" target */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
{{EXCEPTIONS}}			);
			target = {I['appTarget']} /* PinBoard */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{I['gShared']} /* PinBoard */ = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ({I['excShared']} /* Exceptions for "PinBoard" folder in "PinBoard" target */, ); name = PinBoard; path = ../PinBoard; sourceTree = "<group>"; }};
		{I['gApp']} /* App */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = App; sourceTree = "<group>"; }};
		{I['gWidgets']} /* PinBoardWidgets */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = PinBoardWidgets; sourceTree = "<group>"; }};
		{I['gShare']} /* PinBoardShare */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = PinBoardShare; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase('appFrameworks','PBXFrameworksBuildPhase','Frameworks')}{phase('widgetFrameworks','PBXFrameworksBuildPhase','Frameworks')}{phase('shareFrameworks','PBXFrameworksBuildPhase','Frameworks')}/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{I['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{I['gShared']} /* PinBoard */,
				{I['gApp']} /* App */,
				{I['gWidgets']} /* PinBoardWidgets */,
				{I['gShare']} /* PinBoardShare */,
				{I['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{I['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{I['appRef']} /* PinBoard.app */,
				{I['widgetRef']} /* PinBoardWidgets.appex */,
				{I['shareRef']} /* PinBoardShare.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{I['appTarget']} /* PinBoard */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['appConfList']} /* Build configuration list for PBXNativeTarget "PinBoard" */;
			buildPhases = (
				{I['appSources']} /* Sources */,
				{I['appFrameworks']} /* Frameworks */,
				{I['appResources']} /* Resources */,
				{I['appEmbed']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{I['dependency']} /* PBXTargetDependency */,
				{I['shareDependency']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{I['gShared']} /* PinBoard */,
				{I['gApp']} /* App */,
			);
			name = PinBoard;
			productName = PinBoard;
			productReference = {I['appRef']} /* PinBoard.app */;
			productType = "com.apple.product-type.application";
		}};
		{I['widgetTarget']} /* PinBoardWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['widgetConfList']} /* Build configuration list for PBXNativeTarget "PinBoardWidgets" */;
			buildPhases = (
				{I['widgetSources']} /* Sources */,
				{I['widgetFrameworks']} /* Frameworks */,
				{I['widgetResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['gWidgets']} /* PinBoardWidgets */,
			);
			name = PinBoardWidgets;
			productName = PinBoardWidgets;
			productReference = {I['widgetRef']} /* PinBoardWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
		{I['shareTarget']} /* PinBoardShare */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {I['shareConfList']} /* Build configuration list for PBXNativeTarget "PinBoardShare" */;
			buildPhases = (
				{I['shareSources']} /* Sources */,
				{I['shareFrameworks']} /* Frameworks */,
				{I['shareResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{I['gShare']} /* PinBoardShare */,
			);
			name = PinBoardShare;
			productName = PinBoardShare;
			productReference = {I['shareRef']} /* PinBoardShare.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{I['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
			}};
			buildConfigurationList = {I['projConfList']} /* Build configuration list for PBXProject "PinBoard" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {I['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {I['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{I['appTarget']} /* PinBoard */,
				{I['widgetTarget']} /* PinBoardWidgets */,
				{I['shareTarget']} /* PinBoardShare */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase('appResources','PBXResourcesBuildPhase','Resources')}{phase('widgetResources','PBXResourcesBuildPhase','Resources')}{phase('shareResources','PBXResourcesBuildPhase','Resources')}/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase('appSources','PBXSourcesBuildPhase','Sources')}{phase('widgetSources','PBXSourcesBuildPhase','Sources')}{phase('shareSources','PBXSourcesBuildPhase','Sources')}/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{I['dependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['widgetTarget']} /* PinBoardWidgets */;
			targetProxy = {I['proxy']} /* PBXContainerItemProxy */;
		}};
		{I['shareDependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {I['shareTarget']} /* PinBoardShare */;
			targetProxy = {I['shareProxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{cfg('projDebug','Debug',debug)}{cfg('projRelease','Release',release)}{cfg('appDebug','Debug',app)}{cfg('appRelease','Release',app)}{cfg('widgetDebug','Debug',widget)}{cfg('widgetRelease','Release',widget)}{cfg('shareDebug','Debug',share)}{cfg('shareRelease','Release',share)}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
"""
for key, label, d, r in [('projConfList','PBXProject "PinBoard"','projDebug','projRelease'),
                         ('appConfList','PBXNativeTarget "PinBoard"','appDebug','appRelease'),
                         ('widgetConfList','PBXNativeTarget "PinBoardWidgets"','widgetDebug','widgetRelease'),
                         ('shareConfList','PBXNativeTarget "PinBoardShare"','shareDebug','shareRelease')]:
    out += f"""		{I[key]} /* Build configuration list for {label} */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{I[d]} /* Debug */,
				{I[r]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
"""
out += """/* End XCConfigurationList section */
	};
	rootObject = """ + I['project'] + """ /* Project object */;
}
"""
out = out.replace("{EXCEPTIONS}", "".join('\t\t\t\t"%s",\n' % path for path in left_out))
open(os.path.join(HERE, "PinBoard.xcodeproj", "project.pbxproj"), "w").write(out)
print("PinBoard.xcodeproj: %d files left out of the app" % len(left_out))
