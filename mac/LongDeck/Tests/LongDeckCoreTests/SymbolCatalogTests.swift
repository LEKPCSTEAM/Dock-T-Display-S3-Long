import Testing
@testable import LongDeckCore

@Suite struct SymbolCatalogTests {
    @Test func commonSymbolsExist() {
        #expect(SymbolCatalog.common.count == 30)
        #expect(Set(SymbolCatalog.common).count == SymbolCatalog.common.count)
        for name in SymbolCatalog.common { #expect(SymbolCatalog.exists(name), "\(name)") }
    }

    @Test func sampleSymbolsAreCommon() {
        for page in SampleConfig.dev.pages {
            for key in page.keys {
                if case .symbol(let name)? = key.icon { #expect(SymbolCatalog.common.contains(name), "\(name)") }
            }
        }
    }

    @Test func unknownSymbol() {
        #expect(!SymbolCatalog.exists("no.such.symbol.x"))
    }
}
