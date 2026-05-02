import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = SubscriptionManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Go Premium")
                    .font(.largeTitle.bold())
                Text("Unlimited recording. No ads.")
                    .foregroundColor(.secondary)
                Text("Premium unlocks unlimited recording time and removes all ads. Choose the plan that fits you best.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if manager.isLoading {
                    ProgressView()
                        .padding(.top, 12)
                } else if manager.products.isEmpty {
                    VStack(spacing: 20) {
                        Text("Products not available.")
                            .foregroundColor(.secondary)
                        
                        Text("$3.99 / month or $99.99 / lifetime")
                            .font(.headline)
                    }
                } else {
                    ForEach(manager.products.sorted(by: { $0.price < $1.price }), id: \.id) { product in
                        Button {
                            Task {
                                _ = await manager.purchase(product)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(product.displayName)
                                        .font(.headline)
                                    Text(product.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                }

                Button("Restore Purchases") {
                    Task { await manager.restorePurchases() }
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await manager.refreshProducts()
        }
    }
}
