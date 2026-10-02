import Foundation

public struct SteeringState: Sendable, Equatable {

    /// -1 = full left, 0 = center, +1 = full right
    public let steering: Double

    public let angleDegrees: Double
    public let velocity: Double

    /// Нормализованный газ 0...1.
    public let throttle: Double

    /// Нормализованный тормоз 0...1.
    public let brake: Double

    /// Raw среднее давление двух рулевых пальцев.
    public let throttlePressure: Double

    /// Raw pressure пальца в brake zone.
    public let brakePressure: Double

    /// Для обратной совместимости:
    /// среднее давление steering fingers.
    public let pressure: Double

    public let isActive: Bool
    public let isThrottleActive: Bool
    public let isBrakeActive: Bool

    public let contactCount: Int

    public init(
        steering: Double,
        angleDegrees: Double,
        velocity: Double,
        throttle: Double,
        brake: Double,
        throttlePressure: Double,
        brakePressure: Double,
        pressure: Double,
        isActive: Bool,
        isThrottleActive: Bool,
        isBrakeActive: Bool,
        contactCount: Int
    ) {
        self.steering = steering
        self.angleDegrees = angleDegrees
        self.velocity = velocity
        self.throttle = throttle
        self.brake = brake
        self.throttlePressure = throttlePressure
        self.brakePressure = brakePressure
        self.pressure = pressure
        self.isActive = isActive
        self.isThrottleActive = isThrottleActive
        self.isBrakeActive = isBrakeActive
        self.contactCount = contactCount
    }

    public static let idle = SteeringState(
        steering: 0,
        angleDegrees: 0,
        velocity: 0,
        throttle: 0,
        brake: 0,
        throttlePressure: 0,
        brakePressure: 0,
        pressure: 0,
        isActive: false,
        isThrottleActive: false,
        isBrakeActive: false,
        contactCount: 0
    )
}


public struct SteeringConfiguration: Sendable {

    public var travelForFullLock: Double
    public var maximumAngleDegrees: Double

    public var hapticStepDegrees: Double
    public var hapticsEnabled: Bool

    // MARK: Pedals

    /// Pressure, ниже которого газ считается отпущенным.
    public var throttlePressureMin: Double

    /// Pressure, при котором газ достигает 100%.
    public var throttlePressureMax: Double

    /// Pressure, ниже которого тормоз считается отпущенным.
    public var brakePressureMin: Double

    /// Pressure, при котором тормоз достигает 100%.
    public var brakePressureMax: Double

    /// Правая граница brake zone.
    public var brakeZoneMaxX: Double

    /// Нижняя граница brake zone.
    /// В Subsurface Y растёт снизу вверх.
    public var brakeZoneMaxY: Double

    public init(
        travelForFullLock: Double = 0.35,
        maximumAngleDegrees: Double = 180,
        hapticStepDegrees: Double = 10,
        hapticsEnabled: Bool = true,
        throttlePressureMin: Double = 110.0,
        throttlePressureMax: Double = 400.0,
        brakePressureMin: Double = 110.0,
        brakePressureMax: Double = 400.0,
        brakeZoneMaxX: Double = 0.32,
        brakeZoneMaxY: Double = 0.32
    ) {
        self.travelForFullLock = travelForFullLock
        self.maximumAngleDegrees = maximumAngleDegrees
        self.hapticStepDegrees = hapticStepDegrees
        self.hapticsEnabled = hapticsEnabled

        self.throttlePressureMin = throttlePressureMin
        self.throttlePressureMax = throttlePressureMax

        self.brakePressureMin = brakePressureMin
        self.brakePressureMax = brakePressureMax

        self.brakeZoneMaxX = brakeZoneMaxX
        self.brakeZoneMaxY = brakeZoneMaxY
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

    func states() -> AsyncStream<SteeringState>
}
