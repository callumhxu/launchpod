import Foundation
import Testing
@testable import Launchpod

struct SoftwareUpdateConfigurationTests {
    @Test func appBundleEnablesAutomaticChecksWithoutSilentInstallation() throws {
        let info = try #require(Bundle(for: AppDelegate.self).infoDictionary)

        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUAutomaticallyUpdate"] as? Bool != true)
    }

    @Test func appBundleRequiresSignedFeedsAndVerificationBeforeExtraction() throws {
        let info = try #require(Bundle(for: AppDelegate.self).infoDictionary)

        #expect(info["SUShowReleaseNotes"] as? Bool == false)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
                "Sparkle refuses to start when a signed feed is required without verification before extraction.")
    }

    @Test func readsTheSecureFeedAndSigningKeyFromTheSuppliedDictionary() throws {
        let configuration = try #require(SoftwareUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "  https://updates.example.test/launchpod/appcast.xml  ",
            "SUPublicEDKey": "  configured-signing-key  "
        ]))

        #expect(configuration.feedURL == URL(string: "https://updates.example.test/launchpod/appcast.xml"))
        #expect(configuration.publicEDKey == "configured-signing-key")
    }

    @Test(arguments: [
        [:],
        ["SUFeedURL": "https://updates.example.test/appcast.xml"],
        ["SUPublicEDKey": "configured-signing-key"],
        ["SUFeedURL": "", "SUPublicEDKey": "configured-signing-key"],
        ["SUFeedURL": "https://updates.example.test/appcast.xml", "SUPublicEDKey": " \n "],
        ["SUFeedURL": "http://updates.example.test/appcast.xml", "SUPublicEDKey": "configured-signing-key"],
        ["SUFeedURL": "https:///appcast.xml", "SUPublicEDKey": "configured-signing-key"]
    ])
    func missingOrInsecureConfigurationIsUnavailable(infoDictionary: [String: String]) {
        #expect(SoftwareUpdateConfiguration(infoDictionary: infoDictionary) == nil)
    }
}
