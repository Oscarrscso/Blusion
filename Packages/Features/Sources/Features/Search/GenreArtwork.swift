import Foundation

/// TMDb landscape stills for the genres shown on Search's empty page, sized for the tiles.
/// The URLs are deliberately independent of the catalog source; if an addon uses an unrecognised genre,
/// Search keeps the existing coloured tile instead.
enum GenreArtwork {
    private static let urls: [String: String] = [
        "action": "https://image.tmdb.org/t/p/w780/gqrnQA6Xppdl8vIb2eJc58VC1tW.jpg", // Mad Max: Fury Road
        "adventure": "https://image.tmdb.org/t/p/w780/zPACwR32amTNvzId9qyapCWXYDJ.jpg", // Raiders of the Lost Ark
        "animation": "https://image.tmdb.org/t/p/w780/kVd3a9YeLGkoeR50jGEXM6EqseS.jpg", // Spider-Man: Across the Spider-Verse
        "comedy": "https://image.tmdb.org/t/p/w780/jK65srQczOKTpW62wPxwwKztGgE.jpg", // The Grand Budapest Hotel
        "crime": "https://image.tmdb.org/t/p/w780/tSPT36ZKlP2WVHJLM4cQPLSzv3b.jpg", // The Godfather
        "documentary": "https://image.tmdb.org/t/p/w780/1DYpBOVdb7Mzc9DgMCdIBTN1JEC.jpg", // Planet Earth II
        "drama": "https://image.tmdb.org/t/p/w780/fRGxZuo7jJUWQsVg9PREb98Aclp.jpg", // Whiplash
        "family": "https://image.tmdb.org/t/p/w780/kfofK4GzJsJZhCShqZY438c8Y4Y.jpg", // Paddington
        "fantasy": "https://image.tmdb.org/t/p/w780/oiwc338EoBgS4sEI2ixAny4KQKg.jpg", // The Lord of the Rings: The Fellowship of the Ring
        "history": "https://image.tmdb.org/t/p/w780/neeNHeXjMF5fXoCJRsOmkNGC7q.jpg", // Oppenheimer
        "horror": "https://image.tmdb.org/t/p/w780/AdKA2F1SzYPhSZdEbjH1Zh75UVQ.jpg", // The Shining
        "music": "https://image.tmdb.org/t/p/w780/nlPCdZlHtRNcF6C9hzUH4ebmV1w.jpg", // La La Land
        "mystery": "https://image.tmdb.org/t/p/w780/4HWAQu28e2yaWrtupFPGFkdNU7V.jpg", // Knives Out
        "romance": "https://image.tmdb.org/t/p/w780/qA2TyqPldTtoTVY3LKrNIG5g6bH.jpg", // Before Sunrise
        "scifi": "https://image.tmdb.org/t/p/w780/gNdLJU9TxrpGx4dkZidjys3fyy0.jpg", // Blade Runner 2049
        "thriller": "https://image.tmdb.org/t/p/w780/i5H7zusQGsysGQ8i6P361Vnr0n2.jpg", // Se7en
        "war": "https://image.tmdb.org/t/p/w780/2lBOQK06tltt8SQaswgb8d657Mv.jpg", // 1917
        "western": "https://image.tmdb.org/t/p/w780/2oZklIzUbvZXXzIFzv7Hi68d6xf.jpg", // Django Unchained
        "sport": "https://image.tmdb.org/t/p/w780/bacOuUnRBoAO1NjMfsAGX2EKRrS.jpg", // Rocky
        "reality": "https://image.tmdb.org/t/p/w780/1oaj0RL4cM0WuUQJUuarpVWrhb0.jpg", // Survivor
        "kids": "https://image.tmdb.org/t/p/w780/8AqWECiUHnz1Crj69uB9vhiK9Le.jpg", // Toy Story
        "anime": "https://image.tmdb.org/t/p/w780/m4TUa2ciEWSlk37rOsjiSIvZDXE.jpg", // Spirited Away
    ]

    static func imageURL(for genre: String) -> URL? {
        let normalised = String(genre.lowercased().filter(\.isLetter))
        let key: String
        switch normalised {
        case "sciencefiction", "sciencefictionandfantasy", "scifiandfantasy": key = "scifi"
        case "children", "childrens", "kidsandfamily": key = "kids"
        case "realitytv", "realitytelevision": key = "reality"
        case "sports": key = "sport"
        case "historical": key = "history"
        case "actionandadventure": key = "action"
        case "musical", "musicals": key = "music"
        default: key = normalised
        }
        return urls[key].flatMap(URL.init(string:))
    }
}
