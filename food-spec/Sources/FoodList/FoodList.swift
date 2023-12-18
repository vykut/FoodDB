import Foundation
import Database
import ComposableArchitecture
import Shared
import API
import Ads
import FoodDetails
import UserPreferences

@Reducer
public struct FoodList {
    @ObservableState
    public struct State: Equatable {
        var recentFoods: [Food] = []
        var recentFoodsSortingStrategy: SortingStrategy
        var recentFoodsSortingOrder: SortOrder
        var searchQuery = ""
        var isSearchFocused = false
        var isSearching = false
        var searchResults: [Food] = []
        var shouldShowNoResults: Bool = false
        var inlineFood: FoodDetails.State?
        var billboard: Billboard = .init()
        @Presents var destination: Destination.State?

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

        var isSortMenuDisabled: Bool {
            recentFoods.count < 2
        }

        public enum SortingStrategy: String, Codable, Identifiable, Hashable, CaseIterable, Sendable {
            case name
            case energy
            case carbohydrate
            case protein
            case fat

            public var id: Self { self }

            var column: Column {
                switch self {
                    case .name: Column("name")
                    case .energy: Column("energy")
                    case .carbohydrate: Column("carbohydrate")
                    case .protein: Column("protein")
                    case .fat: Column("fatTotal")
                }
            }
        }

        public init() { 
            @Dependency(\.userPreferencesClient) var userPreferencesClient
            let prefs = userPreferencesClient.getPreferences()
            self.recentFoodsSortingStrategy = prefs.foodSortingStrategy ?? .name
            self.recentFoodsSortingOrder = prefs.recentSearchesSortingOrder ?? .forward
        }
    }

    @CasePathable
    public enum Action {
        case onFirstAppear
        case startObservingRecentFoods
        case onRecentFoodsChange([Food])
        case onUserPreferencesChange(UserPreferences)
        case updateSearchQuery(String)
        case updateSearchFocus(Bool)
        case didSelectRecentFood(Food)
        case didSelectSearchResult(Food)
        case didDeleteRecentFoods(IndexSet)
        case startSearching
        case didReceiveSearchFoods([FoodApiModel])
        case inlineFood(FoodDetails.Action)
        case updateRecentFoodsSortingStrategy(State.SortingStrategy)
        case billboard(Billboard)
        case spotlight(Spotlight)
        case showGenericAlert
        case destination(PresentationAction<Destination.Action>)
    }

    enum CancelID {
        case search
        case recentFoodsObservation
    }

    public init() { }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.foodClient) private var foodClient
    @Dependency(\.mainQueue) private var mainQueue
    @Dependency(\.userPreferencesClient) private var userPreferencesClient


    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .onFirstAppear:
                    return .run { send in
                        await send(.startObservingRecentFoods)
                    }.merge(with: .run { [userPreferencesClient] send in
                        let stream = await userPreferencesClient.observeChanges()
                        for await preferences in stream {
                            await send(.onUserPreferencesChange(preferences))
                        }
                    })

                case .startObservingRecentFoods:
                    return .run { [databaseClient, strategy = state.recentFoodsSortingStrategy, order = state.recentFoodsSortingOrder] send in
                        let stream = databaseClient.observeFoods(sortedBy: strategy.column, order: order)
                        for await foods in stream {
                            await send(.onRecentFoodsChange(foods), animation: .default)
                        }
                    }
                    .cancellable(id: CancelID.recentFoodsObservation, cancelInFlight: true)

                case .onRecentFoodsChange(let foods):
                    state.recentFoods = foods
                    if foods.isEmpty && state.searchQuery.isEmpty {
                        state.isSearchFocused = true
                    }
                    return .none

                case .onUserPreferencesChange(let preferences):
                    var shouldRestartDatabaseObservation = false
                    if let newStrategy = preferences.foodSortingStrategy, newStrategy != state.recentFoodsSortingStrategy {
                        state.recentFoodsSortingStrategy = newStrategy
                        shouldRestartDatabaseObservation = true
                    }
                    if let newOrder = preferences.recentSearchesSortingOrder, newOrder != state.recentFoodsSortingOrder {
                        state.recentFoodsSortingOrder = newOrder
                        shouldRestartDatabaseObservation = true
                    }
                    if shouldRestartDatabaseObservation {
                        return .send(.startObservingRecentFoods)
                    } else {
                        return .none
                    }

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
                    state.destination = .foodDetails(.init(food: food))
                    return .none

                case .didSelectSearchResult(let food):
                    state.destination = .foodDetails(.init(food: food))
                    return .run { send in
                        _ = try await databaseClient.insert(food: food)
                    }

                case .didDeleteRecentFoods(let indices):
                    return .run { [recentFoods = state.recentFoods, databaseClient] send in
                        let foodsToDelete = indices.map { recentFoods[$0] }
                        for food in foodsToDelete {
                            try await databaseClient.delete(food: food)
                        }
                    } catch: { error, send in
                        await send(.showGenericAlert)
                    }

                case .inlineFood:
                    return .none

                case .updateRecentFoodsSortingStrategy(let newStrategy):
                    if newStrategy == state.recentFoodsSortingStrategy {
                        state.recentFoodsSortingOrder.toggle()
                    } else {
                        state.recentFoodsSortingStrategy = newStrategy
                        state.recentFoodsSortingOrder = .forward
                    }
                    return .run { [strategy = state.recentFoodsSortingStrategy, order = state.recentFoodsSortingOrder] send in
                        try await userPreferencesClient.setPreferences {
                            $0.foodSortingStrategy = strategy
                            $0.recentSearchesSortingOrder = order
                        }
                        await send(.startObservingRecentFoods)
                    }

                case .showGenericAlert:
                    state.destination = .alert(.init {
                        TextState("Something went wrong. Please try again later.")
                    })
                    return .none

                case .billboard:
                    // handled in BillboardReducer
                    return .none

                case .spotlight:
                    // handled in SpotlightReducer
                    return .none

                case .destination:
                    return .none
            }
        }
        .ifLet(\.inlineFood, action: \.inlineFood) {
            FoodDetails()
        }
        .ifLet(\.$destination, action: \.destination) {
            Destination()
        }
        SpotlightReducer()
        BillboardReducer()
    }

    @Reducer
    public struct Destination {
        @ObservableState
        public enum State: Hashable {
            case foodDetails(FoodDetails.State)
            case alert(AlertState<Action.Alert>)
        }

        @CasePathable
        public enum Action {
            case foodDetails(FoodDetails.Action)
            case alert(Alert)

            @CasePathable
            public enum Alert: Hashable { }
        }

        public var body: some ReducerOf<Self> {
            Scope(state: \.foodDetails, action: \.foodDetails) {
                FoodDetails()
            }
        }
    }
}

fileprivate extension UserPreferences {
    var foodSortingStrategy: FoodList.State.SortingStrategy? {
        get {
            recentSearchesSortingStrategy.flatMap { .init(rawValue: $0) }
        }
        set {
            recentSearchesSortingStrategy = newValue?.rawValue
        }
    }
}
