import Foundation
import Testing
@testable import SocialKit

/// Expected values computed with Node:
/// `((Number(id) / 1e15) * Math.PI).toString(6 ** 2).replace(/(0+|\.)/g, '')` (react-tweet's getToken).
@Suite struct TokenTests {
    static let known: [(String, String)] = [
        ("1", "bhi2ay3f28n"),
        ("20", "6dq1a2xwd93"),
        ("21", "6p7jcdvzsb"),
        ("1234567890", "6iio5bzbwyw"),
        ("266031293945503744", "n7rfhxzwhkd"),
        ("440322224407314432", "12fb9qdo78ad"),
        ("1585341984679469056", "3uchycv2wqc"),
        ("1790461178853359788", "4c8wdzr1fre"),
        ("1866187963364401552", "4iusvwl14bn"),
        ("1942975057040404843", "4pk1avbts1"),
        ("1951004815930302557", "4q99g2dxt3i"),
        ("2006584708126367842", "4v3vdto18l4"),
        ("2041150038659789111", "4y4gmpi1ava"),
        ("2078978440087409066", "51fax766ap"),
        ("2080781584106487853", "51kyupgo3io"),
        ("9007199254740993", "saoujnx4as"),
        ("999999999999999999", "2f9lc2ug9mm"),
    ]

    /// Pseudo-random 19-digit ids (LCG seeded with 12345 in Node).
    static let random: [(String, String)] = [
        ("6551540483048143386", "fvq9rstugp"),
        ("6324834829958810806", "fby1yt54hmu"),
        ("6794614796731233596", "ggxwtuz6lct"),
        ("1726980208831720650", "46pguyq93cl"),
        ("7072738408275345563", "h57nva21zbh"),
        ("7394193413377417325", "hx9jkn6gbk6"),
        ("7938960791922100782", "j8szb8x2wz9"),
        ("5798715652337620258", "e217afjk2qb"),
        ("2089484037875735163", "52cb2s76uo8"),
        ("8713064198439874649", "l4cwcfash9v"),
        ("1113386154703874886", "2p5t9qhir4"),
        ("7313331363660134077", "hq7iah89qqn"),
        ("2793172593682554960", "6rrdlwudn"),
        ("9187244178707646131", "m9qku5cx4uf"),
        ("4192689654286555051", "a5vq112ecbc"),
        ("8197082281727265119", "jvbw5y2ibt"),
        ("1583112773178704380", "3u5hu437zcn"),
        ("3769789335044973492", "94z54nkmiu"),
        ("9729743004675345420", "nl2wbxu94l"),
        ("7535071372253012657", "i9k4htt6uk"),
        ("4360175438734368085", "akhw8314gj"),
        ("8189367053078688383", "junnldglq"),
        ("5357974768465718030", "czkko4ichwn"),
        ("7002214191110666990", "gz23rn3e2vk"),
        ("5892471370921251773", "ea7qt88jc"),
        ("6909420783995910882", "gqyl2wm35e"),
        ("6996604202541414499", "gykhajtdgp"),
        ("3822709324003864526", "99le8lt5p"),
        ("4181910759441000223", "a4xuyprwcf"),
        ("4305287590227943658", "afpgjzgp4ux"),
    ]

    @Test(arguments: known + random)
    func tokenMatchesNode(id: String, token: String) {
        #expect(XSyndication.token(for: id) == token)
    }

    /// `Number.prototype.toString(radix)` for awkward values, also from Node.
    @Test func radixStringsMatchV8() {
        #expect(JSNumber.string(0.5, radix: 36) == "0.i")
        #expect(JSNumber.string(1.0 / 3, radix: 36) == "0.c")
        #expect(JSNumber.string(1.0 / 3, radix: 16) == "0.55555555555554")
        #expect(JSNumber.string(123.456, radix: 36) == "3f.gez4w97ry")
        #expect(JSNumber.string(123.456, radix: 16) == "7b.74bc6a7ef9dc")
        #expect(JSNumber.string(1e21, radix: 36) == "5v1j4f4ds7c000")
        #expect(JSNumber.string(1e21, radix: 16) == "3635c9adc5dea00000")
        #expect(JSNumber.string(9007199254740994, radix: 36) == "2gosa7pa2gy")
        #expect(JSNumber.string(0.1 + 0.2, radix: 36) == "0.asssssssssv")
        #expect(JSNumber.string(0.1 + 0.2, radix: 2) == "0.0100110011001100110011001100110011001100110011001101")
        #expect(JSNumber.string(35.99999999999999, radix: 36) == "z.zzzzzzzzz")
        #expect(JSNumber.string(1e-7, radix: 36) == "0.000061oezo085tl")
        #expect(JSNumber.string(Double.pi, radix: 36) == "3.53i5ab8p5f")
        #expect(JSNumber.string(Double.pi, radix: 2) == "11.001001000011111101101010100010001000010110100011")
        #expect(JSNumber.string(-255, radix: 16) == "-ff")
        #expect(JSNumber.string(0, radix: 36) == "0")
    }

    @Test func syndicationURL() {
        let url = XSyndication.url(for: "20")
        #expect(url.absoluteString == "https://cdn.syndication.twimg.com/tweet-result?id=20&lang=es&token=6dq1a2xwd93")
    }
}
