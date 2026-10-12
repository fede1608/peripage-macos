import Foundation
import Testing
@testable import SocialKit

@Suite struct LinkTests {
    @Test(arguments: [
        "https://x.com/jack/status/20",
        "https://twitter.com/jack/status/20",
        "http://www.twitter.com/jack/status/20?lang=es",
        "https://mobile.twitter.com/jack/status/20",
        "https://mobile.x.com/jack/status/20/",
        "x.com/jack/status/20",
        "https://x.com/jack/status/20/photo/1",
        "https://x.com/i/web/status/20",
        "https://x.com/i/status/20",
        "https://twitter.com/jack/statuses/20",
        "https://fxtwitter.com/jack/status/20",
        "https://vxtwitter.com/jack/status/20",
        "https://fixupx.com/jack/status/20",
        "  <https://x.com/jack/status/20?s=46&t=abc>  ",
        "20",
    ])
    func tweetLinks(_ link: String) {
        #expect(SocialLink.parse(link) == .tweet(id: "20"))
        #expect(SocialFetcher.canHandle(link))
    }

    @Test(arguments: [
        "https://www.instagram.com/p/DeNRLCCF4kk/",
        "https://instagram.com/p/DeNRLCCF4kk",
        "instagram.com/p/DeNRLCCF4kk/?igsh=MWQ1ZGUxMzBkMA==",
        "https://www.instagram.com/reel/DeNRLCCF4kk/?utm_source=ig_web_copy_link",
        "https://www.instagram.com/reels/DeNRLCCF4kk/",
        "https://www.instagram.com/tv/DeNRLCCF4kk/",
        "https://www.instagram.com/natgeo/p/DeNRLCCF4kk/?img_index=2",
        "https://m.instagram.com/p/DeNRLCCF4kk/",
        "https://instagr.am/p/DeNRLCCF4kk/",
        "https://www.ddinstagram.com/p/DeNRLCCF4kk/",
        "https://www.instagram.com/p/DeNRLCCF4kk/embed/captioned/",
    ])
    func instagramLinks(_ link: String) {
        #expect(SocialLink.parse(link) == .instagramPost(shortcode: "DeNRLCCF4kk"))
        #expect(SocialFetcher.canHandle(link))
    }

    @Test func shortcodesWithDashAndUnderscore() {
        #expect(SocialLink.parse("https://www.instagram.com/p/BsOGulcndj-/") == .instagramPost(shortcode: "BsOGulcndj-"))
        #expect(SocialLink.parse("https://www.instagram.com/p/C_x-9ab_Z1q/") == .instagramPost(shortcode: "C_x-9ab_Z1q"))
    }

    @Test func linksThatNeedARedirect() {
        #expect(SocialLink.parse("https://t.co/C9U5NOtGap") == .redirect(URL(string: "https://t.co/C9U5NOtGap")!))
        #expect(SocialLink.parse("https://www.instagram.com/share/p/BAcDeFgHiJ/") == .redirect(URL(string: "https://www.instagram.com/share/p/BAcDeFgHiJ/")!))
        #expect(SocialFetcher.canHandle("https://t.co/C9U5NOtGap"))
    }

    @Test func storiesAreFetchableWithTheirId() {
        #expect(SocialLink.parse("https://www.instagram.com/stories/natgeo/3456789012345678901/") == .instagramStory(user: "natgeo", id: "3456789012345678901"))
        #expect(SocialLink.parse("https://www.instagram.com/stories/natgeo/") == .instagramStory(user: "natgeo", id: nil))
        #expect(SocialFetcher.canHandle("https://www.instagram.com/stories/natgeo/3456789012345678901/"))
    }

    @Test func recognizedButNotFetchable() {
        #expect(SocialLink.parse("https://www.instagram.com/natgeo/") == .instagramProfile(user: "natgeo"))
        #expect(SocialLink.parse("https://x.com/jack") == .xProfile(user: "jack"))
        #expect(!SocialFetcher.canHandle("https://www.instagram.com/natgeo/"))
        #expect(!SocialFetcher.canHandle("https://x.com/jack"))
    }

    @Test(arguments: ["", "hola", "https://example.com/p/DeNRLCCF4kk/", "https://x.com/home", "https://x.com/jack/status/",
                      "https://www.instagram.com/explore/", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "123456789012345678901"])
    func rejected(_ link: String) {
        #expect(!SocialFetcher.canHandle(link))
    }

    @Test func fetchRejectsUnsupportedLinksWithSpanishErrors() async {
        SocialFetcher.isLoggedIn = { _ in false }
        await #expect(throws: SocialError.unsupportedLink) { try await SocialFetcher.fetch("https://example.com") }
        await #expect(throws: SocialError.instagramStory) { try await SocialFetcher.fetch("https://www.instagram.com/stories/natgeo/1/") }
        await #expect(throws: SocialError.profileLink) { try await SocialFetcher.fetch("https://x.com/jack") }
        #expect(SocialError.unsupportedLink.errorDescription?.contains("Pegá el link") == true)
        #expect(SocialError.instagramStory.errorDescription?.contains("iniciá sesión") == true)
        #expect(SocialError.tweetUnavailable.errorDescription?.contains("Iniciar sesión") == true)
    }

    @Test func instagramShortcodeDates() throws {
        // Ids and publication dates confirmed against the embed pages.
        #expect(InstagramID.mediaID(shortcode: "DeNRLCCF4kk") == 4_002_931_168_689_752_356)
        #expect(InstagramID.mediaID(shortcode: "BsOGulcndj-") == 1_949_525_278_281_554_174)
        let egg = try #require(InstagramID.date(shortcode: "BsOGulcndj-"))
        #expect(abs(egg.timeIntervalSince1970 - 1_546_621_545.106) < 0.01)  // 2019-01-04 17:05:45 UTC
        #expect(InstagramID.date(shortcode: "CzX9aB3dEfGhIjKlMnOpQrStUvWxYz012345") == nil)  // private-post style
    }
}
