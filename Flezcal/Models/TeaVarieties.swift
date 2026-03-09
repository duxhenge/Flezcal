import Foundation

/// Curated list of tea varieties for autocomplete suggestions.
/// Users can always type a custom variety not on this list.
enum TeaVarieties {

    // MARK: - Black Tea

    static let black: [String] = [
        "Assam",
        "Ceylon",
        "Darjeeling",
        "Earl Grey",
        "English Breakfast",
        "Irish Breakfast",
        "Keemun",
        "Lapsang Souchong",
        "Masala Chai",
        "Nilgiri",
        "Scottish Breakfast",
        "Yunnan Black",
    ]

    // MARK: - Green Tea

    static let green: [String] = [
        "Bancha",
        "Bi Luo Chun",
        "Dragon Well (Longjing)",
        "Genmaicha",
        "Gunpowder",
        "Gyokuro",
        "Hojicha",
        "Jasmine Green",
        "Kukicha",
        "Sencha",
    ]

    // MARK: - Oolong Tea

    static let oolong: [String] = [
        "Alishan",
        "Da Hong Pao",
        "Dong Ding",
        "Iron Goddess (Tieguanyin)",
        "Milk Oolong (Jin Xuan)",
        "Oriental Beauty",
        "Phoenix Dan Cong",
    ]

    // MARK: - White Tea

    static let white: [String] = [
        "Bai Mu Dan (White Peony)",
        "Silver Needle (Bai Hao Yin Zhen)",
        "Shou Mei",
    ]

    // MARK: - Pu-erh Tea

    static let puerh: [String] = [
        "Ripe Pu-erh (Shou)",
        "Raw Pu-erh (Sheng)",
    ]

    // MARK: - Herbal & Tisanes

    static let herbal: [String] = [
        "Chamomile",
        "Chrysanthemum",
        "Hibiscus",
        "Mint",
        "Rooibos",
        "Yerba Mate",
    ]

    // MARK: - Chai & Spiced

    static let chai: [String] = [
        "Chai Latte",
        "Dirty Chai",
        "Kashmiri Chai (Pink Chai)",
        "Masala Chai",
        "Thai Iced Tea",
        "Turkish Tea (Çay)",
    ]

    // MARK: - Service Styles

    static let serviceStyles: [String] = [
        "Afternoon Tea",
        "Cream Tea",
        "Gongfu Service",
        "High Tea",
        "Tea Flight",
        "Tea Tasting",
    ]

    // MARK: - Combined

    /// All tea varieties across all categories
    static let all: [String] = (black + green + oolong + white + puerh + herbal + chai + serviceStyles).sorted()

    /// Returns varieties matching a search query, case-insensitive
    static func suggestions(for query: String) -> [String] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
