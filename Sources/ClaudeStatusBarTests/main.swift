import TestSupport

// Each phase appends its suites here.
runSuites([
    stateMapperTests(),
    aggregationTests(),
    stateStoreTests(),
    ignoreListTests(),
    hookProcessorTests(),
    statusViewModelTests(),
    notificationCoordinatorTests(),
    settingsJsonMergeTests(),
    hookInstallerTests(),
    floatingSelectionTests(),
    floatingLayoutTests(),
    usageSnapshotTests(),
])
