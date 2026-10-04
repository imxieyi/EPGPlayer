//
//  SearchQueryTests.swift
//  EPGPlayerTests
//
//  SPDX-License-Identifier: MPL-2.0

import Testing
@testable import EPGPlayer

// Regression coverage for a real bug: the generated `Query.init` parameter order must
// stay in sync with `SearchQuery.apiQuery()`'s argument order (ruleId before channelId),
// since Swift matches arguments positionally against the generated memberwise init.
struct SearchQueryTests {
    @Test func apiQueryIncludesRuleAndChannelFilters() {
        let query = SearchQuery(
            keyword: "news",
            channel: SearchChannel(name: "NHK", channelId: 1),
            rule: SearchRule(id: 42, keyword: "news rule"))

        let apiQuery = query.apiQuery(offset: 10)

        #expect(apiQuery.keyword == "news")
        #expect(apiQuery.offset == 10)
        #expect(apiQuery.ruleId == 42)
        #expect(apiQuery.channelId == 1)
        #expect(apiQuery.isHalfWidth == true)
    }

    @Test func apiQueryOmitsFiltersWhenNotSet() {
        let query = SearchQuery(keyword: "", channel: nil)

        let apiQuery = query.apiQuery()

        #expect(apiQuery.offset == nil)
        #expect(apiQuery.ruleId == nil)
        #expect(apiQuery.channelId == nil)
    }
}
