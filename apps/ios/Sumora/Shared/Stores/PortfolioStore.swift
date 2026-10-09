import Foundation
import Observation

@MainActor @Observable
final class PortfolioStore {
    private(set) var snapshot: PortfolioSnapshot?
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    private(set) var errorToast: PortfolioErrorToast?
    @ObservationIgnored private var api: any PortfolioAPI
    @ObservationIgnored private var refreshTask: Task<PortfolioSnapshot, Error>?
    @ObservationIgnored private var generation = UUID()

    init(api: any PortfolioAPI) { self.api = api }

    func refresh() async {
        if let refreshTask {
            _ = try? await refreshTask.value
            return
        }
        isRefreshing = true
        let currentGeneration = generation
        let service = api
        let task = Task { try await service.fetchSnapshot() }
        refreshTask = task
        do {
            let result = try await task.value
            guard generation == currentGeneration else { return }
            snapshot = result
            errorMessage = nil
            errorToast = nil
        } catch is CancellationError {
            // Cancellation preserves the currently displayed snapshot.
        } catch {
            guard generation == currentGeneration else { return }
            if (error as? URLError)?.code != .cancelled {
                let message = error.localizedDescription + (snapshot == nil ? "" : " Showing your last saved data.")
                if errorMessage != message { presentErrorToast(message) }
                errorMessage = message
            }
        }
        guard generation == currentGeneration else { return }
        refreshTask = nil
        isRefreshing = false
    }

    func replaceAPI(_ api: any PortfolioAPI, clearSnapshot: Bool) {
        cancelRefresh()
        self.api = api
        if clearSnapshot { snapshot = nil }
        errorMessage = nil
        errorToast = nil
    }

    func presentErrorToast(_ message: String) {
        errorToast = PortfolioErrorToast(message: message)
    }

    func dismissErrorToast(id: UUID) {
        if errorToast?.id == id { errorToast = nil }
    }

    func cancelRefresh() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }
}

struct PortfolioErrorToast: Identifiable {
    let id = UUID()
    let message: String
}
