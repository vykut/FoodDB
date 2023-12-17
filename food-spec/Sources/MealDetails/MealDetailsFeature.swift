import Foundation
import Shared
import MealForm
import FoodDetails
import FoodComparison
import ComposableArchitecture

@Reducer 
public struct MealDetailsFeature {
    @ObservableState
    public struct State: Hashable {
        var meal: Meal
        var nutritionalValuesPerTotal: Ingredient
        var nutritionalValuesPerServing: Ingredient
        @Presents var mealForm: MealFormFeature.State?
        @Presents var foodDetails: FoodDetailsFeature.State?
        @Presents var foodComparison: FoodComparisonFeature.State?

        public init(meal: Meal) {
            @Dependency(\.nutritionalValuesCalculator) var calculator
            self.meal = meal
            self.nutritionalValuesPerTotal = calculator.nutritionalValues(meal: meal)
            self.nutritionalValuesPerServing = calculator.nutritionalValuesPerServing(meal: meal)
        }
    }

    @CasePathable
    public enum Action {
        case editButtonTapped
        case nutritionalInfoPerServingButtonTapped
        case nutritionalInfoButtonTapped
        case ingredientComparisonButtonTapped
        case ingredientTapped(Ingredient)
        case mealForm(PresentationAction<MealFormFeature.Action>)
        case foodDetails(PresentationAction<FoodDetailsFeature.Action>)
        case foodComparison(PresentationAction<FoodComparisonFeature.Action>)
    }

    public init() { }

    @Dependency(\.nutritionalValuesCalculator) private var calculator

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
                case .editButtonTapped:
                    state.mealForm = .init(meal: state.meal)
                    return .none

                case .nutritionalInfoPerServingButtonTapped:
                    state.foodDetails = .init(
                        food: state.nutritionalValuesPerServing.food,
                        quantity: state.nutritionalValuesPerServing.quantity
                    )
                    return .none

                case .nutritionalInfoButtonTapped:
                    state.foodDetails = .init(
                        food: state.nutritionalValuesPerTotal.food,
                        quantity: state.nutritionalValuesPerTotal.quantity
                    )
                    return .none

                case .ingredientComparisonButtonTapped:
                    let foods = state.meal.ingredients.map(\.foodWithQuantity)
                    state.foodComparison = .init(
                        foods: foods,
                        comparison: .energy,
                        canChangeQuantity: false
                    )
                    return .none

                case .ingredientTapped(let ingredient):
                    state.foodDetails = .init(
                        food: ingredient.food,
                        quantity: ingredient.quantity
                    )
                    return .none

                case .mealForm(.presented(.delegate(.mealSaved(let meal)))):
                    state.meal = meal
                    return .none

                case .mealForm:
                    return .none

                case .foodDetails:
                    return .none

                case .foodComparison:
                    return .none
            }
        }
        .onChange(of: \.meal) { _, newMeal in
            Reduce { state, _ in
                state.nutritionalValuesPerTotal = calculator.nutritionalValues(meal: newMeal)
                state.nutritionalValuesPerServing = calculator.nutritionalValuesPerServing(meal: newMeal)
                return .none
            }
        }
        .ifLet(\.$mealForm, action: \.mealForm) {
            MealFormFeature()
        }
        .ifLet(\.$foodDetails, action: \.foodDetails) {
            FoodDetailsFeature()
        }
        .ifLet(\.$foodComparison, action: \.foodComparison) {
            FoodComparisonFeature()
        }
    }
}
