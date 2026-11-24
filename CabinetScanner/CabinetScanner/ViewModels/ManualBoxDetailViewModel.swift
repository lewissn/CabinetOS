import Foundation

@MainActor
final class ManualBoxDetailViewModel: ObservableObject {
    @Published var box: ManualManifestBox
    @Published var items: [ManualManifestItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    let manifestName: String
    let courierName: String?
    let isManifestFinished: Bool
    /// The job this consignment was raised for: its panels are what scans are
    /// checked against. Nil for one typed by hand, which checks nothing.
    let jobIndexId: String?

    /// Whether scans are checked against the job's ERP export, and if not, why.
    enum PanelCheck {
        case notAJob
        case loading
        case checking(JobPanelList)
        case unchecked(String)
    }
    @Published private(set) var panelCheck: PanelCheck = .loading
    /// The last label refused, kept on screen until the next scan is taken:
    /// the scanner closes on each scan, so a toast is too easily missed.
    @Published var refusal: String?

    private let service = ManualManifestService()
    private let jobService = JobIndexService()
    private var panelsLoad: Task<Void, Never>?

    init(box: ManualManifestBox, manifestName: String, courierName: String?, isManifestFinished: Bool, jobIndexId: String? = nil) {
        self.box = box
        self.manifestName = manifestName
        self.courierName = courierName
        self.isManifestFinished = isManifestFinished
        self.jobIndexId = jobIndexId
        if jobIndexId == nil { panelCheck = .notAJob }
    }

    /// One line on what's checked, for under the count. Nil for a hand-typed consignment.
    var panelCheckLine: String? {
        switch panelCheck {
        case .notAJob, .loading: return nil
        case .checking(let list): return "Scans are checked against \(list.project ?? "the job")'s \(list.panels?.count ?? 0) panels."
        case .unchecked(let reason): return reason
        }
    }

    var panelsAreChecked: Bool {
        if case .checking = panelCheck { return true }
        return false
    }

    /// Start reading the job's panels (again): on opening the box and on pull
    /// to refresh. A scan made meanwhile waits for it.
    private func startPanelsLoad() -> Task<Void, Never>? {
        guard let jobIndexId else {
            panelCheck = .notAJob
            return nil
        }
        let jobService = self.jobService
        let task = Task { @MainActor in
            do {
                let list = try await jobService.jobPanels(jobId: jobIndexId)
                if list.isAvailable {
                    self.panelCheck = .checking(list)
                } else {
                    self.panelCheck = .unchecked(list.reason ?? list.error ?? "Scans aren't checked against this job.")
                }
            } catch {
                self.panelCheck = .unchecked("Couldn't read the job's panels, so scans aren't being checked. Pull down to try again.")
            }
        }
        panelsLoad = task
        return task
    }

    func loadItems() async {
        let panels = startPanelsLoad()
        isLoading = true
        errorMessage = nil
        do {
            items = try await service.fetchItems(boxId: box.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        await panels?.value
    }

    func addScannedItem(triplet: ScanTriplet) async {
        let isDuplicate = items.contains {
            $0.itemType == .label &&
            $0.projectName == triplet.projectName &&
            $0.cabinetName == triplet.cabinetName &&
            $0.partNumber == triplet.partNumber
        }

        if isDuplicate {
            toastMessage = "Duplicate — \(triplet.cabinetName) Part \(triplet.partNumber) already in this box"
            HapticService.error()
            return
        }

        // Checked against the job's panels once they're read: another job's
        // panel, one not on its export, or one already in another box stays out.
        if case .loading = panelCheck { await panelsLoad?.value }
        if case .checking(let list) = panelCheck, case .refused(let why) = list.check(triplet, inBox: box.id) {
            refusal = why
            toastMessage = nil
            HapticService.error()
            return
        }

        do {
            let item = try await service.upsertLabelItem(
                boxId: box.id,
                projectName: triplet.projectName,
                cabinetName: triplet.cabinetName,
                partNumber: triplet.partNumber
            )
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = item
            } else {
                items.append(item)
            }
            HapticService.success()
            HapticService.playTickSound()
            refusal = nil
            let unchecked = jobIndexId != nil && !panelsAreChecked
            toastMessage = "Added \(triplet.cabinetName) — Part \(triplet.partNumber)\(unchecked ? " (not checked)" : "")"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func addManualItem(name: String, quantity: Int) async {
        do {
            let item = try await service.upsertManualItem(
                boxId: box.id,
                itemName: name,
                quantity: quantity
            )
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = item
            } else {
                items.append(item)
            }
            HapticService.success()
            toastMessage = "Added \(name) (x\(item.qty))"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func deleteItem(_ item: ManualManifestItem) async {
        do {
            try await service.deleteItem(id: item.id)
            items.removeAll { $0.id == item.id }
            toastMessage = "Item removed"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func closeBox(lengthMM: Int, widthMM: Int, heightMM: Int, weightKG: Double) async -> Bool {
        do {
            try await service.closeBox(
                id: box.id,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG
            )
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: .closed,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG,
                createdAt: box.createdAt
            )
            HapticService.seal()
            SealCenter.shared.mark(box.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func closeBoxSimple() async -> Bool {
        do {
            try await service.closeBoxSimple(id: box.id)
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: .closed,
                lengthMM: box.lengthMM,
                widthMM: box.widthMM,
                heightMM: box.heightMM,
                weightKG: box.weightKG,
                createdAt: box.createdAt
            )
            HapticService.seal()
            SealCenter.shared.mark(box.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func updateDimensions(lengthMM: Int, widthMM: Int, heightMM: Int, weightKG: Double) async -> Bool {
        do {
            try await service.updateBoxDimensions(
                id: box.id,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG
            )
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: box.status,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG,
                createdAt: box.createdAt
            )
            toastMessage = "Dimensions updated"
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
            try await service.reopenBox(id: box.id)
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: .open,
                lengthMM: box.lengthMM,
                widthMM: box.widthMM,
                heightMM: box.heightMM,
                weightKG: box.weightKG,
                createdAt: box.createdAt
            )
            toastMessage = "Box reopened"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }
}
