import TestSupport

// Each phase appends its suites here.
runSuites([
    stateMapperTests(),
    aggregationTests(),
    stateStoreTests(),
    hookProcessorTests(),
    statusViewModelTests(),
    notificationCoordinatorTests(),
    settingsJsonMergeTests(),
    hookInstallerTests(),
])
