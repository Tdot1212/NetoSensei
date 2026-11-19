import Foundation

actor RoutingEngine {
    static let shared = RoutingEngine()
    private init() {}

    func runTraceroute(to host: String) async -> Result<[RoutingHop], DiagnosticError> {
        .failure(.unknown("IP hop discovery is unavailable; use Endpoint Checks for independent responses."))
    }

    func interpretRoute(_ hops: [RoutingHop]) async -> RoutingInterpretation {
        RoutingInterpretation(hops: hops, diagnosis: "Route not measured", problemType: .normal,
            userFriendlyExplanation: "Endpoint response time does not identify intermediate network hops.", recommendations: [])
    }
}
