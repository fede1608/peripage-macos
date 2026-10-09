import Foundation
import Testing
@testable import ResourceStore

// MARK: Iconify

private let iconifySearchJSON = """
{"icons":["mdi:cat","solar:cat-bold","tabler:cat"],"total":32,"limit":32,"start":0,
 "collections":{
  "mdi":{"name":"Material Design Icons","total":7447,"author":{"name":"Pictogrammers","url":"https://github.com/Templarian/MaterialDesign"},
         "license":{"title":"Apache 2.0","spdx":"Apache-2.0","url":"https://github.com/Templarian/MaterialDesign/blob/master/LICENSE"},
         "samples":["account-check","bell-alert-outline"],"height":24,"category":"Material","tags":["Precise Shapes"],"palette":false},
  "solar":{"name":"Solar","total":8706,"author":{"name":"480 Design","url":"https://www.figma.com/community/file/1166831539721848736"},
           "license":{"title":"CC BY 4.0","spdx":"CC-BY-4.0","url":"https://creativecommons.org/licenses/by/4.0/"},
           "height":24,"category":"UI 24px","palette":false},
  "tabler":{"name":"Tabler Icons","total":6238,"version":"3.49.0","author":{"name":"Paweł Kuna"},
            "license":{"title":"MIT","spdx":"MIT"},"height":[24,32],"displayHeight":24,"category":"UI 24px","palette":false}
 },
 "request":{"query":"cat palette:false","limit":"32"}}
"""

@Test func iconifySearchParsing() throws {
    let result = try Iconify.parseSearch(Data(iconifySearchJSON.utf8))
    #expect(result.icons == ["mdi:cat", "solar:cat-bold", "tabler:cat"])
    #expect(result.total == 32)
    #expect(result.collections["mdi"]?.license?.title == "Apache 2.0")
    #expect(result.collections["tabler"]?.author?.name == "Paweł Kuna")

    let mdi = try #require(Iconify.item(id: "mdi:cat", collection: result.collections["mdi"]))
    #expect(mdi.info.source == "Iconify · Material Design Icons")
    #expect(mdi.info.license == "Apache 2.0")
    #expect(mdi.info.attribution == nil)
    #expect(mdi.style == .lineArt)
    guard case .svg(let url) = mdi.source else { Issue.record("expected SVG source"); return }
    #expect(url.absoluteString == "https://api.iconify.design/mdi/cat.svg?height=1024&color=%23000000")

    // CC BY sets need a credit line.
    let solar = try #require(Iconify.item(id: "solar:cat-bold", collection: result.collections["solar"]))
    #expect(solar.title == "cat bold")
    #expect(solar.info.attribution == "Ícono “cat bold” de Solar por 480 Design, CC BY 4.0")
}

@Test func iconifyEmptySearch() throws {
    let result = try Iconify.parseSearch(Data(#"{"icons":[],"total":0,"limit":32,"start":0,"collections":{}}"#.utf8))
    #expect(result.icons.isEmpty)
    #expect(throws: StoreError.badData) { try Iconify.parseSearch(Data("Bad request".utf8)) }
}

@Test func iconifyCollectionsParsing() throws {
    let json = """
    {"mdi":{"name":"Material Design Icons","total":7447,"license":{"title":"Apache 2.0","spdx":"Apache-2.0"},"height":24,"category":"Material","palette":false},
     "twemoji":{"name":"Twitter Emoji","total":3668,"license":{"title":"CC BY 4.0","spdx":"CC-BY-4.0"},"height":[36,72],"category":"Emoji","palette":true},
     "fa":{"name":"Font Awesome 4","total":678,"license":{"title":"OFL-1.1"},"hidden":true}}
    """
    let sets = try Iconify.parseCollections(Data(json.utf8))
    #expect(sets.count == 3)
    #expect(sets["mdi"]?.isMonochrome == true)
    #expect(sets["twemoji"]?.isMonochrome == false)
    #expect(sets["fa"]?.hidden == true)
}

@Test func iconifyListingParsing() throws {
    let json = """
    {"prefix":"mdi","total":5,"title":"Material Design Icons",
     "categories":{"Animal":["cat","dog"],"Agriculture":["barn"]},"uncategorized":["zzz","cat"],"hidden":["zzz"]}
    """
    let listing = try Iconify.parseListing(Data(json.utf8))
    #expect(listing.allIcons == ["barn", "cat", "dog"])
}

@Test func iconifyURLs() {
    let url = Iconify.searchURL(query: "cat", limit: 10, prefix: "mdi", colorful: false)
    #expect(url.absoluteString == "https://api.iconify.design/search?query=cat%20palette:false&limit=32&prefix=mdi")
    #expect(Iconify.split("icon-park-outline:cat-face")! == ("icon-park-outline", "cat-face"))
    #expect(Iconify.split("broken") == nil)
}

// MARK: OpenMoji

private let openMojiJSON = """
[
 {"emoji":"😀","hexcode":"1F600","group":"smileys-emotion","subgroups":"face-smiling","annotation":"grinning face",
  "tags":"face, grin, grinning, happy","openmoji_tags":"smile, happy","openmoji_author":"Emily Jäger","openmoji_date":"2018-04-18",
  "skintone":"","skintone_combination":"","skintone_base_emoji":"","skintone_base_hexcode":"","unicode":1,"order":1},
 {"emoji":"🐱","hexcode":"1F431","group":"animals-nature","subgroups":"animal-mammal","annotation":"cat face",
  "tags":"cat, face, pet","openmoji_tags":"","openmoji_author":"Antonia Wagner","skintone":"","skintone_base_hexcode":"","unicode":1,"order":2},
 {"emoji":"❤️","hexcode":"2764-FE0F","group":"smileys-emotion","subgroups":"heart","annotation":"red heart",
  "tags":"heart","openmoji_tags":"love","skintone":"","skintone_base_hexcode":"","order":3},
 {"emoji":"👶🏽","hexcode":"1F476-1F3FD","group":"people-body","subgroups":"person","annotation":"baby: medium skin tone",
  "tags":"","openmoji_tags":"","skintone":3,"skintone_combination":"single","skintone_base_emoji":"👶","skintone_base_hexcode":"1F476","unicode":1,"order":522},
 {"emoji":"🏻","hexcode":"1F3FB","group":"component","subgroups":"skin-tone","annotation":"light skin tone","tags":"","skintone":1,"skintone_base_hexcode":"","order":""},
 {"emoji":"🍦","hexcode":"1F366","group":"food-drink","subgroups":"food-sweet","annotation":"soft ice cream",
  "tags":"cream, dessert, ice, icecream, soft, sweet","openmoji_tags":"","skintone":"","skintone_base_hexcode":"","order":900},
 {"emoji":"","hexcode":"","annotation":"broken row"}
]
"""

@Test func openMojiCatalogParsing() throws {
    let entries = try OpenMoji.parseCatalog(Data(openMojiJSON.utf8))
    #expect(entries.map(\.hexcode) == ["1F600", "1F431", "2764-FE0F", "1F366"])
    let grin = entries[0]
    #expect(grin.tags == ["face", "grin", "grinning", "happy", "smile", "happy"])
    #expect(grin.author == "Emily Jäger")

    let item = OpenMoji.item(entries[1], color: false)
    #expect(item.id == "openmoji:1F431:black")
    #expect(item.info.license == "CC BY-SA 4.0")
    #expect(item.info.attribution?.contains("OpenMoji") == true)
    guard case .svg(let url) = item.source else { Issue.record("expected SVG"); return }
    #expect(url.absoluteString == "https://cdn.jsdelivr.net/npm/openmoji@17.0.0/black/svg/1F431.svg")
    if case .svg(let color) = OpenMoji.item(entries[1], color: true).source {
        #expect(color.absoluteString.hasSuffix("/color/svg/1F431.svg"))
    }
}

@Test func openMojiSpanishSearch() throws {
    let entries = try OpenMoji.parseCatalog(Data(openMojiJSON.utf8))
    #expect(OpenMoji.search(entries, query: "gato", group: nil).map(\.hexcode) == ["1F431"])
    #expect(OpenMoji.search(entries, query: "Corazón", group: nil).map(\.hexcode) == ["2764-FE0F"])
    #expect(OpenMoji.search(entries, query: "helado", group: nil).map(\.hexcode) == ["1F366"])
    #expect(OpenMoji.search(entries, query: "happy", group: nil).map(\.hexcode) == ["1F600"])
    // Equal scores keep catalog order.
    #expect(OpenMoji.search(entries, query: "face", group: nil).map(\.hexcode) == ["1F600", "1F431"])
    #expect(OpenMoji.search(entries, query: "", group: "food-drink").map(\.hexcode) == ["1F366"])
    #expect(OpenMoji.search(entries, query: "gato", group: "food-drink").isEmpty)
    #expect(OpenMoji.search(entries, query: "zzzz", group: nil).isEmpty)
}

// MARK: Openverse

private let openverseJSON = """
{"result_count":240,"page_count":12,"page_size":20,"page":1,"results":[
 {"id":"1c5442f6-6bb6-4ab7-b603-f598e7579dd2","title":"Cat Fish 2","indexed_on":"2020-04-24T11:47:34.004529Z",
  "foreign_landing_url":"https://www.flickr.com/photos/32426194@N00/3481540500",
  "url":"https://live.staticflickr.com/3313/3481540500_c846c62863_b.jpg","creator":"admiller",
  "creator_url":"https://www.flickr.com/photos/32426194@N00","license":"by","license_version":"2.0",
  "license_url":"https://creativecommons.org/licenses/by/2.0/","provider":"flickr","source":"flickr","category":null,
  "filesize":null,"filetype":null,"tags":[{"name":"cat","accuracy":null}],
  "attribution":"\\"Cat Fish 2\\" by admiller is licensed under CC BY 2.0.","mature":false,"height":1024,"width":716,
  "thumbnail":"https://api.openverse.org/v1/images/1c5442f6-6bb6-4ab7-b603-f598e7579dd2/thumb/"},
 {"id":"abc","title":null,"url":"https://upload.wikimedia.org/x.png","creator":null,"license":"cc0","license_version":"1.0",
  "provider":"wikimedia","source":"wikimedia","height":null,"width":null,"thumbnail":null}
]}
"""

@Test func openverseParsing() throws {
    let result = try Openverse.parse(Data(openverseJSON.utf8))
    #expect(result.resultCount == 240)
    #expect(result.pageCount == 12)
    #expect(result.results.count == 2)

    let cat = try #require(Openverse.item(result.results[0]))
    #expect(cat.title == "Cat Fish 2")
    #expect(cat.info.source == "Openverse · Flickr")
    #expect(cat.info.license == "CC BY 2.0")
    #expect(cat.info.attribution == "“Cat Fish 2” de admiller, CC BY 2.0 · https://www.flickr.com/photos/32426194@N00/3481540500")
    #expect(cat.pixelSize == CGSize(width: 716, height: 1024))
    #expect(cat.licenseURL?.absoluteString == "https://creativecommons.org/licenses/by/2.0/")
    guard case .remote(let thumb, let full) = cat.source else { Issue.record("expected remote"); return }
    #expect(thumb.absoluteString.hasSuffix("/thumb/"))
    #expect(full.host == "live.staticflickr.com")

    let untitled = try #require(Openverse.item(result.results[1]))
    #expect(untitled.title == "Sin título")
    #expect(untitled.info.license == "CC0 1.0")
    #expect(untitled.info.source == "Openverse · Wikimedia Commons")
    guard case .remote(let fallbackThumb, _) = untitled.source else { return }
    #expect(fallbackThumb.absoluteString == "https://api.openverse.org/v1/images/abc/thumb/")
}

@Test func openverseLicenseNames() {
    #expect(Openverse.licenseName(code: "by-sa", version: "4.0") == "CC BY-SA 4.0")
    #expect(Openverse.licenseName(code: "by-nc-nd", version: "2.0") == "CC BY-NC-ND 2.0")
    #expect(Openverse.licenseName(code: "cc0", version: nil) == "CC0 1.0")
    #expect(Openverse.licenseName(code: "pdm", version: "1.0") == "Dominio público")
    let url = Openverse.searchURL(query: "cat", page: 2, category: .illustration)
    #expect(url.absoluteString == "https://api.openverse.org/v1/images/?q=cat&page_size=20&page=2&category=illustration")
}

// MARK: Google Fonts

private let fontsMetadataJSON = """
{"axisRegistry":[{"tag":"wght","displayName":"Weight","min":1.0,"defaultValue":400.0,"max":1000.0}],
 "familyMetadataList":[
  {"family":"Lobster","displayName":null,"category":"Display","stroke":"Sans Serif","size":100,"subsets":["menu","latin","latin-ext"],
   "fonts":{"400":{"thickness":7,"slant":1,"width":5,"lineHeight":1.25}},"axes":[],"designers":["Impallari Type"],"popularity":150,"isOpenSource":true},
  {"family":"Inter","category":"Sans Serif","subsets":["latin"],
   "fonts":{"100":{},"400":{},"400i":{},"700":{},"900":{}},"axes":[{"tag":"wght","min":100.0,"max":900.0,"defaultValue":400.0}],
   "designers":["Rasmus Andersson"],"popularity":5},
  {"family":"Noto Sans JP","category":"Sans Serif","subsets":["japanese"],"fonts":{"400":{}},"designers":["Google"],"popularity":10},
  {"family":"Light Only","category":"Serif","subsets":["latin"],"fonts":{"300":{},"300i":{}},"designers":[],"popularity":900}
 ],
 "promotedScript":null}
"""

@Test func googleFontsMetadataParsing() throws {
    for prefix in ["", ")]}'\n"] {
        let families = try GoogleFonts.parseMetadata(Data((prefix + fontsMetadataJSON).utf8))
        // Latin only, most popular first.
        #expect(families.map(\.family) == ["Inter", "Lobster", "Light Only"])
        let inter = families[0]
        #expect(inter.regularWeight == 400)
        #expect(inter.boldWeight == 700)
        #expect(inter.categoryTitle == "Sans serif")
        #expect(families[1].boldWeight == nil)
        #expect(families[1].categoryTitle == "Decorativas")
        #expect(families[2].regularWeight == 300)
    }
}

@Test func googleFontsCSSParsing() {
    let css = """
    @font-face {
      font-family: 'Open Sans';
      font-style: normal;
      font-weight: 400;
      font-stretch: normal;
      src: url(https://fonts.gstatic.com/s/opensans/v44/memSYaGs126MiZpBA-UvWbX2vVnXBbObj2OVZyOOSr4dVJWUgsjZ0C4n.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Open Sans';
      font-style: normal;
      font-weight: 700;
      src: url(https://fonts.gstatic.com/s/opensans/v44/memSYaGs126MiZpBA-UvWbX2vVnXBbObj2OVZyOOSr4dVJWUgsg-1y4n.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Open Sans';
      font-style: italic;
      font-weight: 400;
      src: url(https://fonts.gstatic.com/s/opensans/v44/italic.ttf) format('truetype');
    }
    @font-face {
      font-family: 'Lobster';
      font-style: normal;
      font-weight: 400;
      src: url(https://fonts.gstatic.com/s/lobster/v32/neILzCirqoswsqX9_oY.woff) format('woff');
    }
    @font-face {
      font-family: 'Lobster';
      font-style: normal;
      font-weight: 400;
      src: url(https://fonts.gstatic.com/l/font?kit=neILzCirqoswsqX9_oW0OIkDYqa95RJ8wEfls_5a&skey=7ed805a363b4659c&v=v32) format('truetype');
    }
    """
    let faces = GoogleFonts.parseCSS(css)
    #expect(faces.count == 5)
    #expect(faces[0] == GoogleFonts.FontFace(
        family: "Open Sans", weight: 400, italic: false,
        url: URL(string: "https://fonts.gstatic.com/s/opensans/v44/memSYaGs126MiZpBA-UvWbX2vVnXBbObj2OVZyOOSr4dVJWUgsjZ0C4n.ttf")!,
        format: "truetype"))
    #expect(faces[1].weight == 700)
    #expect(faces[2].italic)
    let ttf = GoogleFonts.trueTypeFaces(faces)
    #expect(ttf.count == 4)
    #expect(!ttf.contains { $0.format == "woff" })
    #expect(ttf.last?.url.absoluteString.contains("kit=") == true)
}

@Test func googleFontsCSSURL() {
    #expect(GoogleFonts.cssURL(family: "Open Sans", weights: [400, 700]).absoluteString
            == "https://fonts.googleapis.com/css2?family=Open+Sans:wght@400;700")
    #expect(GoogleFonts.cssURL(family: "Lobster", weights: [400]).absoluteString
            == "https://fonts.googleapis.com/css2?family=Lobster")
    #expect(GoogleFonts.cssURL(family: "Lobster", weights: [400], text: "Lobster ñ").absoluteString
            == "https://fonts.googleapis.com/css2?family=Lobster&text=Lobster%20%C3%B1")
}

// MARK: Spanish keywords

@Test func spanishKeywordMapping() {
    #expect(SpanishKeywords.englishQuery(for: "gato") == "cat")
    #expect(SpanishKeywords.englishQuery(for: "  Corazón ") == "heart")
    #expect(SpanishKeywords.englishQuery(for: "flores") == "flower")
    #expect(SpanishKeywords.englishQuery(for: "perros") == "dog")
    #expect(SpanishKeywords.englishQuery(for: "gato negro") == "cat black")
    #expect(SpanishKeywords.englishQuery(for: "helado") == "ice cream")
    #expect(SpanishKeywords.englishQuery(for: "cumpleaños") == "birthday")
    #expect(SpanishKeywords.englishQuery(for: "estrella") == "star")
    #expect(SpanishKeywords.englishQuery(for: "comida") == "food")
    #expect(SpanishKeywords.englishQuery(for: "fiesta") == "party")
    // Already English or unknown: no rewrite.
    #expect(SpanishKeywords.englishQuery(for: "cat") == nil)
    #expect(SpanishKeywords.englishQuery(for: "pizza") == nil)
    #expect(SpanishKeywords.englishQuery(for: "xyzzy") == nil)
    #expect(SpanishKeywords.translate(word: "Árbol") == "tree")
}
