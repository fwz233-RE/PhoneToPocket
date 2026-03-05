import SwiftUI

@Observable
final class SettingsViewModel {
    let settings = AppSettings.shared
    let metaGlassesService: MetaGlassesService

    init(metaGlassesService: MetaGlassesService) {
        self.metaGlassesService = metaGlassesService
    }
}
