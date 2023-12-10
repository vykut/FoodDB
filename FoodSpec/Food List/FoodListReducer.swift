//
//  FoodListReducer.swift
//  FoodSpec
//
//  Created by Victor Socaciu on 02/12/2023.
//

import Foundation
import GRDB
import ComposableArchitecture

@Reducer
struct FoodListReducer {
    @ObservableState
    struct State: Equatable {
        var recentFoods: [Food] = []
        var recentFoodsSortingStrategy: Food.SortingStrategy = .name
        var recentFoodsSortingOrder: SortOrder = .forward
        var searchQuery = ""
        var isSearchFocused = false
        var isSearching = false
        var searchResults: [Food] = []
        var shouldShowNoResults: Bool = false
        var inlineFood: FoodDetailsReducer.State?
        var billboard: Billboard = .init()
        @Presents var foodDetails: FoodDetailsReducer.State?
        @Presents var foodComparison: FoodComparisonReducer.State?
        @Presents var alert: AlertState<Action.Alert>?

        var shouldShowRecentSearches: Bool {
            searchQuery.isEmpty && !recentFoods.isEmpty
        }

        var shouldShowPrompt: Bool {
            searchQuery.isEmpty && recentFoods.isEmpty && !shouldShowNoResults
        }

        var shouldShowSpinner: Bool {
            isSearching
        }

        var shouldShowSearchResults: Bool {
            isSearchFocused && !searchResults.isEmpty && inlineFood == nil
        }

        var isCompareButtonDisabled: Bool {
            recentFoods.count < 2
        }

        var isSortMenuDisabled: Bool {
            recentFoods.count < 2
        }
    }

    @CasePathable
    enum Action {
        case onAppear
        case updateFromUserDefaults(Food.SortingStrategy?, SortOrder?)
        case startObservingRecentFoods
        case didFetchRecentFoods([Food])
        case updateSearchQuery(String)
        case updateSearchFocus(Bool)
        case didSelectRecentFood(Food)
        case didSelectSearchResult(Food)
        case didDeleteRecentFoods(IndexSet)
        case startSearching
        case didReceiveSearchFoods([FoodApiModel])
        case foodDetails(PresentationAction<FoodDetailsReducer.Action>)
        case inlineFood(FoodDetailsReducer.Action)
        case didTapCompare
        case foodComparison(PresentationAction<FoodComparisonReducer.Action>)
        case updateRecentFoodsSortingStrategy(Food.SortingStrategy)
        case billboard(Billboard)
        case spotlight(Spotlight)
        case showGenericAlert
        case alert(PresentationAction<Alert>)

        @CasePathable
        enum Alert: Equatable {
            case showGenericAlert
        }
    }

    enum CancelID {
        case search
        case recentFoodsObservation
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.foodClient) private var foodClient
    @Dependency(\.mainQueue) private var mainQueue
    @Dependency(\.userDefaults) private var userDefaults

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .onAppear:
                    return .run { send in
                        let strategy = userDefaults.recentSearchesSortingStrategy
                        let order = userDefaults.recentSearchesSortingOrder
                        await send(.updateFromUserDefaults(strategy, order))
                        await send(.startObservingRecentFoods)
                    }

                case .updateFromUserDefaults(let strategy, let order):
                    if let strategy {
                        state.recentFoodsSortingStrategy = strategy
                    }
                    if let order {
                        state.recentFoodsSortingOrder = order
                    }
                    return .none

                case .startObservingRecentFoods:
                    return .run { [strategy = state.recentFoodsSortingStrategy, order = state.recentFoodsSortingOrder] send in
                        let stream = databaseClient.observeFoods(sortedBy: strategy, order: order)
                        for await foods in stream {
                            await send(.didFetchRecentFoods(foods), animation: .default)
                        }
                    }
                    .cancellable(id: CancelID.recentFoodsObservation, cancelInFlight: true)

                case .didFetchRecentFoods(let foods):
                    state.recentFoods = foods
                    if foods.isEmpty && state.searchQuery.isEmpty {
                        state.isSearchFocused = true
                    }
                    return .none

                case .updateSearchQuery(let query):
                    guard state.searchQuery != query else { return .none }
                    state.searchQuery = query
                    state.shouldShowNoResults = false
                    state.searchResults = []
                    state.inlineFood = nil
                    if query.isEmpty {
                        state.isSearching = false
                        return .cancel(id: CancelID.search)
                    } else {
                        return .run { [searchQuery = state.searchQuery] send in
                            await send(.startSearching)
                            let foods = try await foodClient.getFoods(query: searchQuery)
                            await send(.didReceiveSearchFoods(foods))
                        } catch: { error, send in
                            await send(.didReceiveSearchFoods([]))
                            await send(.showGenericAlert)
                        }
                        .debounce(id: CancelID.search, for: .milliseconds(300), scheduler: mainQueue)
                    }

                case .startSearching:
                    state.isSearching = true
                    return .none

                case .didReceiveSearchFoods(let foods):
                    state.isSearching = false
                    if foods.isEmpty {
                        state.shouldShowNoResults = true
                    } else if foods.count == 1 {
                        let food = Food(foodApiModel: foods[0])
                        state.inlineFood = .init(food: food)
                        return .run { send in
                            _ = try await databaseClient.insert(food: food)
                        }
                    } else {
                        state.searchResults = foods.map { .init(foodApiModel: $0) }
                    }
                    return .none

                case .updateSearchFocus(let focus):
                    guard state.isSearchFocused != focus else { return .none }
                    state.isSearchFocused = focus
                    if !focus {
                        state.inlineFood = nil
                    }
                    return .none

                case .didSelectRecentFood(let food):
                    state.foodDetails = .init(food: food)
                    return .none

                case .didSelectSearchResult(let food):
                    state.foodDetails = .init(food: food)
                    return .run { send in
                        _ = try await databaseClient.insert(food: food)
                    }

                case .didDeleteRecentFoods(let indices):
                    return .run { [recentFoods = state.recentFoods] send in
                        let foodsToDelete = indices.map { recentFoods[$0] }
                        for food in foodsToDelete {
                            try await databaseClient.delete(food: food)
                        }
                    } catch: { error, send in
                        await send(.showGenericAlert)
                    }

                case .foodDetails:
                    return .none

                case .inlineFood:
                    return .none

                case .didTapCompare:
                    state.foodComparison = .init(
                        foods: state.recentFoods
                    )
                    return .none

                case .foodComparison:
                    return .none

                case .updateRecentFoodsSortingStrategy(let newStrategy):
                    if newStrategy == state.recentFoodsSortingStrategy {
                        state.recentFoodsSortingOrder.toggle()
                    } else {
                        state.recentFoodsSortingStrategy = newStrategy
                        state.recentFoodsSortingOrder = .forward
                    }
                    return .run { [strategy = state.recentFoodsSortingStrategy, order = state.recentFoodsSortingOrder] send in
                        userDefaults.recentSearchesSortingStrategy = strategy
                        userDefaults.recentSearchesSortingOrder = order
                        await send(.startObservingRecentFoods)
                    }

                case .showGenericAlert:
                    state.alert =  .init {
                        TextState("Something went wrong. Please try again later.")
                    }
                    return .none

                case .billboard:
                    // handled in BillboardReducer
                    return .none

                case .spotlight:
                    // handled in SpotlightReducer
                    return .none

                case .alert:
                    return .none
            }
        }
        .ifLet(\.$foodDetails, action: \.foodDetails) {
            FoodDetailsReducer()
        }
        .ifLet(\.$foodComparison, action: \.foodComparison) {
            FoodComparisonReducer()
        }
        .ifLet(\.$alert, action: \.alert)
        SpotlightReducer()
        BillboardReducer()
    }
}

extension SortOrder {
    mutating func toggle() {
        self = switch self {
            case .forward: .reverse
            case .reverse: .forward
        }
    }
}
