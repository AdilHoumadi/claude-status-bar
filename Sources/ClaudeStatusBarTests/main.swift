import TestSupport

// Each phase appends its suites here.
runSuites([
    stateMapperTests(),
    aggregationTests(),
    stateStoreTests(),
    ignoreListTests(),
    hookProcessorTests(),
    statusViewModelTests(),
    desktopSessionSourceTests(),
    notificationCoordinatorTests(),
    settingsJsonMergeTests(),
    hookInstallerTests(),
    floatingSelectionTests(),
    floatingLayoutTests(),
])
