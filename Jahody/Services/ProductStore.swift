import Foundation
import FirebaseFirestore

/// Číselník produktů (kolekce `products`) + správa v Nastavení.
@MainActor
final class ProductStore: ObservableObject {
    @Published private(set) var products: [Product] = []

    private var listener: ListenerRegistration?
    private var didAttemptSeed = false

    private var collection: CollectionReference {
        Firestore.firestore().collection("products")
    }

    /// Produkty pro zadávání objednávky (jen aktivní, seřazené).
    var activeProducts: [Product] {
        products.filter(\.isActive)
    }

    func start() {
        guard listener == nil else { return }
        listener = collection
            .order(by: "sortOrder")
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    self.products = snapshot.documents.compactMap { document in
                        guard var product = try? document.data(as: Product.self) else { return nil }
                        product.id = document.documentID
                        return product
                    }
                    // Prázdný číselník potvrzený serverem → naplnit výchozími produkty.
                    if snapshot.documents.isEmpty, !snapshot.metadata.isFromCache, !self.didAttemptSeed {
                        self.didAttemptSeed = true
                        self.seedDefaults()
                    }
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        products = []
        didAttemptSeed = false
    }

    /// Idempotentní naplnění výchozími produkty (pevná ID dokumentů).
    private func seedDefaults() {
        let batch = Firestore.firestore().batch()
        for product in Product.defaults {
            let ref = collection.document(product.id)
            _ = try? batch.setData(from: product, forDocument: ref)
        }
        batch.commit()
    }

    // MARK: - Správa číselníku

    @discardableResult
    func add(name: String, unit: ProductUnit, price: Double? = nil) -> Product {
        let product = Product(
            name: name,
            unit: unit,
            isActive: true,
            sortOrder: (products.map(\.sortOrder).max() ?? -1) + 1,
            price: price
        )
        try? collection.document(product.id).setData(from: product)
        return product
    }

    func rename(_ product: Product, to newName: String) {
        collection.document(product.id).updateData(["name": newName])
    }

    func setPrice(_ product: Product, price: Double?) {
        if let price {
            collection.document(product.id).updateData(["price": price])
        } else {
            collection.document(product.id).updateData(["price": FieldValue.delete()])
        }
    }

    func setActive(_ product: Product, isActive: Bool) {
        collection.document(product.id).updateData(["isActive": isActive])
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = products
        reordered.move(fromOffsets: source, toOffset: destination)
        let batch = Firestore.firestore().batch()
        for (index, product) in reordered.enumerated() where product.sortOrder != index {
            batch.updateData(["sortOrder": index], forDocument: collection.document(product.id))
        }
        batch.commit()
    }
}
