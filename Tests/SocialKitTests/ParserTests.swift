import Foundation
import Testing
@testable import SocialKit

@Suite struct XParserTests {
    func draft(_ json: String) throws -> PostDraft {
        guard case .post(let draft) = try XParser.parse(Data(json.utf8)) else {
            Issue.record("expected a post")
            throw CancellationError()
        }
        return draft
    }

    @Test func plainTweet() throws {
        let d = try draft(Fixtures.xJack20)
        #expect(d.post.platform == .x)
        #expect(d.post.authorName == "jack")
        #expect(d.post.handle == "jack")
        #expect(d.post.text == "just setting up my twttr")
        #expect(d.post.likes == 310_173)
        #expect(d.post.replies == 18_074)
        #expect(d.post.reposts == nil)
        #expect(d.post.date == Date(timeIntervalSince1970: 1_142_974_214))
        #expect(d.post.url?.absoluteString == "https://x.com/jack/status/20")
        #expect(d.imageURLs.isEmpty)
        #expect(d.avatarURL?.absoluteString == "https://pbs.twimg.com/profile_images/1661201415899951105/azNjKOSH_400x400.jpg")
    }

    @Test func photoTweetDropsTheMediaLink() throws {
        let d = try draft(Fixtures.xEllenPhoto)
        #expect(d.post.text == "If only Bradley's arm was longer. Best photo ever. #oscars")
        #expect(d.imageURLs.map(\.absoluteString) == ["https://pbs.twimg.com/media/BhxWutnCEAAtEQ6?format=jpg&name=900x900"])
    }

    @Test func replyPrefixIsRemoved() throws {
        let d = try draft(Fixtures.xReply)
        #expect(d.post.text.hasPrefix("There are some technical and performance reasons"))
        #expect(!d.post.text.contains("@esaagar"))
        #expect(d.post.handle == "NASAAdmin")
    }

    @Test func quotedTweetIsAppendedWithItsMedia() throws {
        let d = try draft(Fixtures.xQuote)
        #expect(d.post.text.hasPrefix("Former astronaut Mark Kelly says Artemis II"))
        #expect(d.post.text.contains("\n\n@SenMarkKelly: “The Artemis missions are going to take astronauts back"))
        #expect(!d.post.text.contains("t.co"))
        #expect(d.imageURLs.map(\.absoluteString) == ["https://pbs.twimg.com/amplify_video_thumb/1951001027873808384/img/KUtA0FSTXizoq01z.jpg"])
    }

    @Test func htmlEntitiesAreDecoded() throws {
        let d = try draft(Fixtures.xEntities)
        #expect(d.post.text.contains("V3 should be built & tested"))
        #expect(!d.post.text.contains("&amp;"))
        #expect(d.post.text.hasSuffix("7500 tons."))
    }

    @Test func linksShowTheirDisplayURL() throws {
        let d = try draft(Fixtures.xLinkAndPhoto)
        #expect(d.post.text.hasPrefix("Tianwen-2 unverified mission timeline:"))
        #expect(d.post.text.contains("🚀 Launch: May 29, 2025"))
        #expect(d.post.text.hasSuffix("Source: m.weibo.cn/detail/5154207…"))
        #expect(!d.post.text.contains("t.co"))
        #expect(d.imageURLs.count == 1)
    }

    @Test func longPostsAreMarkedAsTruncated() throws {
        let d = try draft(Fixtures.xNoteTweet)
        #expect(d.post.text.hasSuffix("But…"))
        #expect(d.post.text.contains("39-year-old"))
        #expect(d.post.handle == "TheAthleticFC")
        #expect(d.post.authorName == "The Athletic | Football")
    }

    @Test func videoGivesItsPoster() throws {
        let d = try draft(Fixtures.xVideo)
        #expect(d.post.authorName == "油井 亀美也　Kimiya.Yui")
        #expect(d.post.text.hasSuffix("(動画を短縮する為、16倍速に編集しています)"))
        #expect(d.imageURLs.map(\.absoluteString) == ["https://pbs.twimg.com/amplify_video_thumb/2006540875283804160/img/150VXOai7NnBNKlN.jpg"])
    }

    @Test func multiplePhotos() throws {
        let d = try draft(Fixtures.xMultiPhoto)
        #expect(d.imageURLs.count == 4)
        #expect(d.imageURLs.allSatisfy { $0.absoluteString.hasSuffix("?format=jpg&name=900x900") })
        #expect(d.imageURLs.first?.absoluteString.hasPrefix("https://pbs.twimg.com/media/GvbVOjdW8AAHcwp") == true)
        #expect(d.post.likes == 18_673)
    }

    @Test func tombstoneAndEmpty() throws {
        guard case .tombstone = try XParser.parse(Data(#"{"__typename":"TweetTombstone","tombstone":{"text":{"text":"This Post is unavailable."}}}"#.utf8)) else {
            Issue.record("expected tombstone")
            return
        }
        guard case .notFound = try XParser.parse(Data("{}".utf8)) else {
            Issue.record("expected notFound")
            return
        }
        #expect(throws: SocialError.unreadable(.x)) { try XParser.parse(Data("<!DOCTYPE html>".utf8)) }
    }
}

@Suite struct InstagramParserTests {
    @Test func singlePhotoFromHTML() throws {
        let d = try InstagramParser.parse(html: Fixtures.igSingleHTML, shortcode: "DeNRLCCF4kk")
        #expect(d.post.platform == .instagram)
        #expect(d.post.handle == "natgeo")
        #expect(d.post.authorName.isEmpty)
        #expect(d.post.text.hasPrefix("In the Alaska Peninsula, a brown bear surrounds a school of sockeye salmon"))
        #expect(d.post.text.contains("Photographer @mikerigney told National Geographic"))
        #expect(d.post.text.contains("\"easily one of the most beautiful natural displays I've ever seen.\""))
        #expect(d.post.text.hasSuffix("\n\nSee more Photos of the Day at the link in bio."))
        #expect(d.post.likes == 111_768)
        #expect(d.post.replies == 199)
        #expect(d.post.url?.absoluteString == "https://www.instagram.com/p/DeNRLCCF4kk/")
        // Date decoded from the shortcode: 2026-10-07 20:56:42 UTC.
        #expect(abs((d.post.date?.timeIntervalSince1970 ?? 0) - 1_791_406_602.461) < 0.01)
        // 1080 px rendition from the srcset (not the full 1439 px, not a hover-card thumbnail).
        #expect(d.imageURLs.count == 1)
        #expect(d.imageURLs.first?.absoluteString.contains("841815809_18705347188019133") == true)
        #expect(d.imageURLs.first?.absoluteString.contains("s1080x1080") == true)
        #expect(d.avatarURL?.absoluteString.contains("683576066_18653628823019133") == true)
    }

    @Test func carouselFromContextJSON() throws {
        let d = try InstagramParser.parse(html: Fixtures.igCarouselHTML, shortcode: "DeK9VDdF33T")
        #expect(d.post.handle == "natgeo")
        #expect(d.post.text.hasPrefix("Presented by @Rolex. Hunted for their scales and meat"))
        #expect(d.post.text.hasSuffix("Photographs by @marcuswestbergphotography"))
        #expect(d.post.likes == 137_332)
        #expect(d.post.replies == 222)
        #expect(d.imageURLs.count == 2)
        #expect(d.imageURLs[0].absoluteString.contains("837837859_18705047239019133") && d.imageURLs[0].absoluteString.contains("p1080x1080"))
        #expect(d.imageURLs[1].absoluteString.contains("838628706_18705047284019133") && d.imageURLs[1].absoluteString.contains("s1080x1080"))
        #expect(d.avatarURL?.absoluteString.hasPrefix("https://scontent.cdninstagram.com/") == true)
    }

    @Test func reelGivesItsCover() throws {
        let d = try InstagramParser.parse(html: Fixtures.igReelHTML, shortcode: "DePpLegAuKI")
        #expect(d.post.handle == "natgeo")
        #expect(d.post.text.hasPrefix("Many orphaned giant anteater pups in Brazil"))
        #expect(d.post.likes == 45_688)
        #expect(d.post.replies == 155)
        #expect(d.imageURLs.count == 1)
        #expect(d.imageURLs.first?.absoluteString.contains("839913705_18705672832019133") == true)
    }

    @Test func brokenEmbedIsReportedAsUnavailable() {
        #expect(throws: SocialError.instagramUnavailable) {
            try InstagramParser.parse(html: Fixtures.igBrokenHTML, shortcode: "AAAAAAAAAAA")
        }
    }

    @Test func loginWallAndGarbage() {
        #expect(throws: SocialError.instagramLogin) {
            try InstagramParser.parse(html: #"<html><body><form id="loginForm" action="/accounts/login/ajax/"></form></body></html>"#, shortcode: "x")
        }
        #expect(throws: SocialError.unreadable(.instagram)) {
            try InstagramParser.parse(html: "<html><body>Hola</body></html>", shortcode: "x")
        }
    }

    @Test func htmlHelpers() {
        #expect(HTMLText.decodeEntities("&#064;natgeo &amp; &quot;hi&quot; &#039;x&#039; &#x1F600; &bogus; a&b") == "@natgeo & \"hi\" 'x' 😀 &bogus; a&b")
        #expect(HTMLText.plainText("Hola<br />mundo <a href=\"/x\">#tag</a>") == "Hola\nmundo #tag")
        #expect(HTMLText.integer(in: "View all 3,771,887 comments") == 3_771_887)
        #expect(HTMLText.bestSource(srcset: "a.jpg 1440w, b.jpg 1080w, c.jpg 640w", target: 1000) == "b.jpg")
        #expect(HTMLText.bestSource(srcset: "a.jpg 584w, b.jpg 480w", target: 1000) == "a.jpg")
    }
}

@Suite struct FxTwitterTests {
    @Test func parsesCountsAndNoteText() throws {
        let json = #"{"code":200,"message":"OK","tweet":{"text":"Texto completo &amp; largo","retweets":2512696,"likes":1861535,"replies":158754,"is_note_tweet":true}}"#
        let extras = try #require(FxTwitter.parse(Data(json.utf8)))
        #expect(extras.reposts == 2512696 && extras.likes == 1861535 && extras.replies == 158754)
        #expect(extras.fullText == "Texto completo & largo")
        let short = #"{"code":200,"tweet":{"text":"hola","retweets":3,"is_note_tweet":false}}"#
        #expect(FxTwitter.parse(Data(short.utf8))?.fullText == nil)
        #expect(FxTwitter.parse(Data(#"{"code":404,"message":"NOT_FOUND"}"#.utf8)) == nil)
    }

    @Test func mergeFillsRepostsAndKeepsQuote() {
        var draft = PostDraft(post: SocialPost(platform: .x, text: "Empieza el post…\n\n@otro: “cita”", likes: 10, replies: 2))
        FxTwitter.merge(FxTwitter.Extras(reposts: 5, likes: 99, replies: 1, fullText: "Empieza el post y sigue"), into: &draft)
        #expect(draft.post.reposts == 5 && draft.post.likes == 10 && draft.post.replies == 2)
        #expect(draft.post.text == "Empieza el post y sigue\n\n@otro: “cita”")
    }
}
