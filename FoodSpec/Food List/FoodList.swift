//
//  ContentView.swift
//  FoodSpec
//
//  Created by Victor Socaciu on 29/11/2023.
//

import SwiftUI
import SwiftData
import ComposableArchitecture

struct FoodList: View {
    @Bindable var store: StoreOf<FoodListReducer>

    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: self.$store.navigationStack.sending(\.updateNavigationStack)) {
            List {
                if self.store.shouldShowRecentSearches {
                    recentSearches
                }
                if self.store.shouldShowPrompt {
                    ContentUnavailableView("Search for food", systemImage: "magnifyingglass")
                }
                if self.store.shouldShowSearchResults {
                    searchResultsList
                }
                if self.store.shouldShowNoResults {
                    ContentUnavailableView.search(text: self.store.searchQuery)
                }
            }
            .listStyle(.sidebar)
            .searchable(
                text: self.$store.searchQuery.sending(\.updateSearchQuery),
                isPresented: self.$store.isSearchFocused.sending(\.updateSearchFocus)
            )
            .overlay {
                if self.store.isSearching {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: FoodDetailsReducer.State.self) { food in
                FoodDetails(store: .init(initialState: food) {
                    FoodDetailsReducer()
                })
            }
        }
        .onAppear {
            self.store.send(.onAppear)
        }
    }

    private var recentSearches: some View {
        Section {
            ForEach(self.store.recentFoods) { item in
                Button {
                    self.store.send(.didSelectRecentFood(item))
                } label: {
                    Text(item.name.capitalized)
                }
            }
            .onDelete(perform: deleteItems)
        } header: {
            Text("Recent Searches")
        }
    }

    private var searchResultsList: some View {
        Section {
            ForEach(self.store.searchResults, id: \.self) { item in
                Button {
                    self.store.send(.didSelectSearchResult(item))
                } label: {
                    Text(item.name.capitalized)
                }
            }
        } header: {
            Text("Results")
        }
    }

    private func deleteItems(offsets: IndexSet) {
        self.store.send(.didDeleteRecentFoods(offsets), animation: .default)
    }
}

#Preview {
    FoodList(
        store: .init(
            initialState: FoodListReducer.State(),
            reducer: {
                FoodListReducer()
                    ._printChanges()
            }
        )
    )
}
