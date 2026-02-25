import Foundation

@MainActor
final class BoxDetailViewModel: ObservableObject {
    @Published var box: Box
    @Published var items: [BoxItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    let manifestId: String
    let consignmentId: String
    let customerName: String
    let manifestName: String
    private let api: APIServiceProtocol
    private let realtime = RealtimeService()

    var shippingMethod: String {
        let name = manifestName
        guard let firstDigit = name.firstIndex(where: { $0.isNumber }) else { return name }
        return String(name[name.startIndex..<firstDigit]).trimmingCharacters(in: .whitespaces)
    }

    init(box: Box, manifestId: String, consignmentId: String, customerName: String, manifestName: String, api: APIServiceProtocol = ServiceContainer.shared.api) {
        self.box = box
        self.manifestId = manifestId
        self.consignmentId = consignmentId
        self.customerName = customerName
        self.manifestName = manifestName
        self.api = api
    }

    func loadBoxDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let (updatedBox, boxItems) = try await api.fetchBoxDetail(boxId: box.id)
            self.box = updatedBox
            self.items = boxItems
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func startPolling() {
        realtime.startPolling { [weak self] in
            guard let self = self else { return }
            await self.refreshQuietly()
        }
    }

    func stopPolling() {
        realtime.stopPolling()
    }

    func deleteItem(_ item: BoxItem) async {
        do {
            try await api.deleteBoxItem(boxItemId: item.id)
            items.removeAll { $0.id == item.id }
            toastMessage = "Item removed"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func closeBox() async -> Bool {
        do {
            let closed = try await api.closeBox(boxId: box.id)
            self.box = closed
            toastMessage = "Box closed"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func reopenBox() async -> Bool {
        do {
            try await api.reopenBox(boxId: box.id, consignmentId: consignmentId)
            let (updatedBox, _) = try await api.fetchBoxDetail(boxId: box.id)
            self.box = updatedBox
            toastMessage = "Box reopened"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func deleteBox() async -> Bool {
        do {
            try await api.deleteBox(boxId: box.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    private func refreshQuietly() async {
        do {
            let (updatedBox, boxItems) = try await api.fetchBoxDetail(boxId: box.id)
            await MainActor.run {
                self.box = updatedBox
                self.items = boxItems
            }
        } catch {
            // Silently ignore polling errors
        }
    }
}
