"""Generate a dependency-free Xcode project. Run after adding Swift source files."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
objects = {}
def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value):
    return json.dumps(str(value), ensure_ascii=False)
def add(name, body):
    key = uid(name)
    objects[key] = body
    return key
def listing(values):
    return '(' + ', '.join(values) + ',)'

app_files = sorted((root / 'LiangZhu').rglob('*.swift'))
test_files = sorted((root / 'LiangZhuTests').glob('*.swift'))
references = []
app_builds, test_builds = [], []
for files, builds in [(app_files, app_builds), (test_files, test_builds)]:
    for file in files:
        path = str(file.relative_to(root))
        ref = add('ref:' + path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = "<group>";')
        references.append(ref)
        builds.append(add('build:' + path, f'isa = PBXBuildFile; fileRef = {ref};'))
resource_builds = []
for path, file_type in [('LiangZhu/Assets.xcassets', 'folder.assetcatalog'), ('LiangZhu/PrivacyInfo.xcprivacy', 'text.xml')]:
    ref = add('ref:' + path, f'isa = PBXFileReference; lastKnownFileType = {file_type}; path = {q(path)}; sourceTree = "<group>";')
    references.append(ref)
    resource_builds.append(add('build:' + path, f'isa = PBXBuildFile; fileRef = {ref};'))
plist = add('plist', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = LiangZhu/Info.plist; sourceTree = "<group>";')
references.append(plist)
app_product = add('appProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LiangZhu.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('testProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LiangZhuTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; name = Products; children = {listing([app_product, test_product])}; sourceTree = "<group>";')
main_group = add('mainGroup', f'isa = PBXGroup; children = {listing(references + [products])}; sourceTree = "<group>";')

project_settings = {
    'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0',
    'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES',
    'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES',
    'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic', 'SWIFT_EMIT_LOC_STRINGS': 'YES',
}
app_settings = {'PRODUCT_BUNDLE_IDENTIFIER': 'com.liangzhu.survey', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'INFOPLIST_FILE': 'LiangZhu/Info.plist', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor', 'ENABLE_PREVIEWS': 'YES',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks'}
test_settings = {'PRODUCT_BUNDLE_IDENTIFIER': 'com.liangzhu.survey.tests', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/LiangZhu.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LiangZhu',
    'BUNDLE_LOADER': '$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @loader_path/Frameworks'}
def config_list(name, base):
    configs = []
    for mode in ['Debug', 'Release']:
        settings = dict(base)
        if name == 'project':
            settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
                'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym',
                'ENABLE_TESTABILITY': 'YES' if mode == 'Debug' else 'NO'})
            if mode == 'Debug':
                settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
        text = ' '.join(f'{k} = {q(v)};' for k, v in settings.items())
        configs.append(add(name + ':' + mode, f'isa = XCBuildConfiguration; buildSettings = {{ {text} }}; name = {mode};'))
    return add(name + ':configs', f'isa = XCConfigurationList; buildConfigurations = {listing(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = config_list('project', project_settings)
app_configs = config_list('app', app_settings)
test_configs = config_list('tests', test_settings)
def phases(name, sources, resources):
    return [add(name + ':sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {listing(sources) if sources else "()"}; runOnlyForDeploymentPostprocessing = 0;'),
        add(name + ':frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;'),
        add(name + ':resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {listing(resources) if resources else "()"}; runOnlyForDeploymentPostprocessing = 0;')]
app_phases = phases('app', app_builds, resource_builds)
test_phases = phases('tests', test_builds, [])
app_id = uid('appTarget')
project_id = uid('projectRoot')
proxy = add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = LiangZhu;')
dependency = add('dependency', f'isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};')
add('appTarget', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {listing(app_phases)}; buildRules = (); dependencies = (); name = LiangZhu; productName = LiangZhu; productReference = {app_product}; productType = "com.apple.product-type.application";')
test_id = add('testTarget', f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {listing(test_phases)}; buildRules = (); dependencies = ({dependency},); name = LiangZhuTests; productName = LiangZhuTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
add('projectRoot', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {app_id} = {{ CreatedOnToolsVersion = 27.0; }}; {test_id} = {{ CreatedOnToolsVersion = 27.0; TestTargetID = {app_id}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base,); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({app_id}, {test_id},);')
content = '// !$*UTF8*$!\n{\n archiveVersion = 1; classes = {}; objectVersion = 56;\n objects = {\n'
content += '\n'.join(f'  {key} = {{ {value} }};' for key, value in objects.items())
content += f'\n }}; rootObject = {project_id};\n}}\n'
(root / 'LiangZhu.xcodeproj/project.pbxproj').write_text(content)
def buildable(target_id, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:LiangZhu.xcodeproj"/>'
app_ref = buildable(app_id, 'LiangZhu', 'LiangZhu.app')
test_ref = buildable(test_id, 'LiangZhuTests', 'LiangZhuTests.xctest')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root / 'LiangZhu.xcodeproj/xcshareddata/xcschemes/LiangZhu.xcscheme').write_text(scheme)
print('Generated LiangZhu.xcodeproj')
