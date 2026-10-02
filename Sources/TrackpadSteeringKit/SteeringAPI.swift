import Foundation

public struct SteeringState: Sendable, Equatable {
    /// -1 = full left, 0 = center, +1 = full right
    public let steering: Double

    public let angleDegrees: Double
    public let velocity: Double
    public let pressure: Double
    public let isActive: Bool
    public let contactCount: Int

    public init(
        steering: Double,
        angleDegrees: Double,
        velocity: Double,
        pressure: Double,
        isActive: Bool,
        contactCount: Int
    ) {
        self.steering = steering
        self.angleDegrees = angleDegrees
        self.velocity = velocity
        self.pressure = pressure
        self.isActive = isActive
        self.contactCount = contactCount
    }

    public static let idle = SteeringState(
        steering: 0,
        angleDegrees: 0,
        velocity: 0,
        pressure: 0,
        isActive: false,
        contactCount: 0
    )
}

public struct SteeringConfiguration: Sendable {
    public var travelForFullLock: Double
    public var maximumAngleDegrees: Double
    public var hapticStepDegrees: Double
    public var hapticsEnabled: Bool

    public init(
        travelForFullLock: Double = 0.35,
        maximumAngleDegrees: Double = 180,
        hapticStepDegrees: Double = 10,
        hapticsEnabled: Bool = true
    ) {
        self.travelForFullLock = travelForFullLock
        self.maximumAngleDegrees = maximumAngleDegrees
        self.hapticStepDegrees = hapticStepDegrees
        self.hapticsEnabled = hapticsEnabled
    }

    public static let `default` = SteeringConfiguration()
}

@MainActor
public protocol SteeringControllerProtocol: AnyObject {
    var state: SteeringState { get }
    var configuration: SteeringConfiguration { get set }

    func start()
    func stop()
    func recenter()
}
