import Foundation
import Testing
@testable import SocialKit

@Suite struct SessionTests {
    @Test func shortcodeToMediaID() {
        #expect(InstagramIDs.mediaID(shortcode: "BsOGulcndj-") == "1949525278281554174")
        #expect(InstagramIDs.mediaID(shortcode: "DeNRLCCF4kk") == "4002931168689752356")
        // Private-post links append extra characters after the 11 that encode the id.
        #expect(InstagramIDs.mediaID(shortcode: "DeNRLCCF4kkAbCdEfGhIjKlMnOpQrStUvWxYz012") == "4002931168689752356")
        #expect(InstagramIDs.mediaID(shortcode: "abc$") == nil)
    }

    @Test func parsesCarouselMediaInfo() throws {
        let json = #"""
        {"items":[{"pk":"4002931168689752356","taken_at":1791400000,"like_count":12,"comment_count":3,
          "user":{"username":"amiga","full_name":"Mi Amiga","profile_pic_url":"https://scontent.cdninstagram.com/a.jpg"},
          "caption":{"text":"Cumple 🎂"},
          "carousel_media":[
            {"image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/small1.jpg","width":320},{"url":"https://scontent.cdninstagram.com/big1.jpg","width":1080}]}},
            {"image_versions2":{"candidates":[{"url":"https://scontent.cdninstagram.com/big2.jpg","width":1080}]}}]}],"status":"ok"}
        """#
        let info = try InstagramAPI.decode(InstagramAPI.MediaInfo.self, Data(json.utf8))
        let draft = InstagramAPI.draft(from: try #require(info.items?.first), url: nil)
        #expect(draft.post.handle == "amiga" && draft.post.authorName == "Mi Amiga" && draft.post.text == "Cumple 🎂")
        #expect(draft.post.likes == 12 && draft.post.replies == 3)
        #expect(draft.imageURLs.map(\.lastPathComponent) == ["big1.jpg", "big2.jpg"])
        #expect(draft.post.date == Date(timeIntervalSince1970: 1_791_400_000))
    }

    @Test func parsesStoryReel() throws {
        let json = #"""
        {"reels_media":[{"user":{"username":"amiga"},"items":[
          {"pk":111,"id":"111_99","taken_at":1791400000,"image_versions2":{"candidates":[{"url":"https://x.cdninstagram.com/s1.jpg","width":720}]}},
          {"pk":"222","id":"222_99","taken_at":1791400500,"image_versions2":{"candidates":[{"url":"https://x.cdninstagram.com/s2.jpg","width":720}]}}]}]}
        """#
        let reels = try InstagramAPI.decode(InstagramAPI.ReelsMedia.self, Data(json.utf8))
        let items = try #require(reels.reelsMedia?.first?.items)
        #expect(items.map { $0.pk?.value } == ["111", "222"])
        #expect(items[1].bestImageURL?.lastPathComponent == "s2.jpg")
    }

    @Test func largeXPhotos() {
        #expect(XPageScript.largePhoto("https://pbs.twimg.com/media/ABC?format=jpg&name=small") == "https://pbs.twimg.com/media/ABC?format=jpg&name=large")
        #expect(XPageScript.largePhoto("https://pbs.twimg.com/media/ABC?format=png") == "https://pbs.twimg.com/media/ABC?format=png&name=large")
    }
}

@Suite struct XCountTests {
    @Test(arguments: [("1234 Replies. Reply", 1234), ("1.234 respuestas", 1234), ("158 mil", 158_000), ("2 M", 2_000_000),
                      ("1,9 M", 1_900_000), ("12.5K", 12_500), ("7", 7), ("3 mil M", 3_000_000_000)])
    func parsesCounts(_ raw: String, _ expected: Int) {
        #expect(XPageScript.count(raw) == expected)
    }

    @Test func emptyCount() {
        #expect(XPageScript.count("Responder") == nil)
        #expect(XPageScript.count(nil) == nil)
    }
}
