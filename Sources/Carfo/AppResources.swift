import Foundation

enum AppResources {
    static var bundle: Bundle {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main
        }
        return Bundle.module
    }
}
