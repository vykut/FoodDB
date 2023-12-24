import Foundation
import ComposableArchitecture
import Spotlight
import CoreSpotlight
import Database

// TODO: Move to AppReducer

@Reducer
struct SpotlightReducer {
    typealias State = FoodList.State
    typealias Action = FoodList.Action

    @Dependency(\.spotlightClient) var spotlightClient
    @Dependency(\.databaseClient) var databaseClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .foodObservation(.updateFoods(let newFoods)):
                    return .run { _ in
                        try await spotlightClient.indexFoods(foods: newFoods)
                    } catch: { _, error in
                        dump(error)
                    }

                case .spotlight(.handleSelectedFood(let activity)):
                    guard let foodName = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return .none }
                    return .run { send in
                        guard let food = try await databaseClient.getFood(name: foodName) else { return }
                        await send(.didSelectRecentFood(food))
                    }

                case .spotlight(.handleSelectedFood(let activity)):
                    guard let searchString = activity.userInfo?[CSSearchQueryString] as? String else { return .none }
                    return .run { [destination = state.destination, isSearchFocused = state.foodSearch.isFocused] send in
                        if destination != nil {
                            await send(.destination(.dismiss))
                        }
//                        if !isSearchFocused {
//                            await send(.foodSearch(.updateFocus(true)))
//                        }
                        await send(.foodSearch(.updateQuery(searchString)))
                    }

                default:
                    return .none
            }
        }
    }
}
