import Foundation

extension Bundle {
    private static var fitpalBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func fitpalResourceURL(name: String, ext: String) -> URL? {
        if let url = fitpalBundle.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = fitpalBundle.url(forResource: name, withExtension: ext, subdirectory: "Models") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Models")
    }
}
