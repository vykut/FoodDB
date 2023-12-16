import SwiftUI
import Shared
import MealForm
import MealDetails
import ComposableArchitecture

public struct MealList: View {
    @Bindable var store: StoreOf<MealListFeature>

    public init(store: StoreOf<MealListFeature>) {
        self.store = store
    }

    public var body: some View {
        List {
            if !store.meals.isEmpty {
                mealsSection
            }
        }
        .foregroundStyle(.primary)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.plusButtonTapped)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationTitle("Meals")
        .onFirstAppear {
            store.send(.onFirstAppear)
        }
        .navigationDestination(
            item: self.$store.scope(state: \.mealDetails, action: \.mealDetails),
            destination: { store in
                MealDetails(store: store)
            }
        )
        .sheet(
            item: $store.scope(state: \.mealForm, action: \.mealForm),
            content: { store in
                NavigationStack {
                    MealForm(store: store)
                }
                .interactiveDismissDisabled()
            }
        )
    }

    private var mealsSection: some View {
        Section {
            ForEach(store.meals, id: \.id) { meal in
                ListButton {
                    self.store.send(.mealTapped(meal))
                } label: {
                    LabeledListRow(
                        title: meal.name.capitalized,
                        footnote: "Per serving: \(meal.nutritionalValuesPerServingSize.food.nutritionalSummary)"
                    )
                }
            }
            .onDelete { offsets in
                self.store.send(.onDelete(offsets))
            }
        }
    }
}

#Preview {
    MealList(
        store: .init(
            initialState: MealListFeature.State(),
            reducer: {
                MealListFeature()
            }
        )
    )
}
