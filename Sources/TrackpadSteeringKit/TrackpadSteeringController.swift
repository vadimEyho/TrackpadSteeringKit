import Foundation
import Subsurface


public struct SteeringContact: Sendable, Identifiable, Equatable {

    public let id: Int32

    public let x: Double
    public let y: Double

    public let velocityX: Double
    public let velocityY: Double

    public let pressure: Double
    public let density: Double
    public let capacitance: Double

    public let majorAxis: Double
    public let minorAxis: Double

    public var vx: Double { velocityX }
    public var vy: Double { velocityY }
}


@MainActor
public final class TrackpadSteeringController:
    SteeringControllerProtocol
{
    public private(set) var state: SteeringState = .idle

    public var configuration: SteeringConfiguration

    public private(set) var contacts: [SteeringContact] = []

    public private(set) var steeringContacts: [SteeringContact] = []

    public private(set) var brakeContact: SteeringContact?

    public private(set) var deviceName =
        "Waiting for trackpad…"

    public private(set) var frame: Int32 = 0

    public private(set) var telemetryFPS: Double = 0


    private let monitor = SubsurfaceMonitor()

    private var task: Task<Void, Never>?

    private var steeringIDs: Set<Int32> = []

    private var startX: Double?

    private var hapticActuator: SubsurfaceActuator?

    private var lastHapticStep: Int?

    private var lastEdge = 0

    private var previousSteering = 0.0

    private var previousTimestamp =
        CFAbsoluteTimeGetCurrent()

    private var frameCounter = 0

    private var fpsStart =
        CFAbsoluteTimeGetCurrent()

    private var continuations:
        [UUID: AsyncStream<SteeringState>.Continuation] = [:]


    public init(
        configuration: SteeringConfiguration = .default
    ) {
        self.configuration = configuration
    }


    public func start() {

        guard task == nil else { return }

        monitor.start()

        if let device = monitor.activeDevices.first {

            deviceName = device.name

            if configuration.hapticsEnabled,
               let actuator = device.actuator,
               actuator.open()
            {
                hapticActuator = actuator
            }
        }

        task = Task { [weak self] in

            guard let self else { return }

            for await (device, contacts)
                in monitor.contacts()
            {
                guard !Task.isCancelled else { break }

                self.process(
                    device: device,
                    rawContacts: contacts
                )
            }
        }
    }


    public func stop() {

        task?.cancel()
        task = nil

        hapticActuator?.close()
        hapticActuator = nil

        reset()
    }


    public func recenter() {

        guard steeringContacts.count == 2 else {
            startX = nil
            return
        }

        startX =
            (
                steeringContacts[0].x +
                steeringContacts[1].x
            ) / 2.0

        previousSteering = 0

        publish(
            steering: 0,
            velocity: 0
        )
    }


    public func states()
        -> AsyncStream<SteeringState>
    {
        let id = UUID()

        return AsyncStream { continuation in

            continuations[id] = continuation

            continuation.yield(state)

            continuation.onTermination = {
                @Sendable [weak self] _ in

                Task { @MainActor in
                    self?.continuations
                        .removeValue(forKey: id)
                }
            }
        }
    }


    private func process(
        device: SubsurfaceDevice,
        rawContacts: [MTContact]
    ) {
        deviceName = device.name

        let active = rawContacts
            .filter {
                $0.contactState != .outOfRange
            }
            .map {
                SteeringContact(
                    id: $0.id,
                    x: Double(
                        $0.normalizedVector.position.x
                    ),
                    y: Double(
                        $0.normalizedVector.position.y
                    ),
                    velocityX: Double(
                        $0.normalizedVector.velocity.x
                    ),
                    velocityY: Double(
                        $0.normalizedVector.velocity.y
                    ),
                    pressure: Double($0.pressure),
                    density: Double($0.density),
                    capacitance:
                        Double($0.totalCapacitance),
                    majorAxis: Double($0.majorAxis),
                    minorAxis: Double($0.minorAxis)
                )
            }

        contacts = active.sorted {
            $0.x < $1.x
        }

        if let first = rawContacts.first {
            frame = first.frame
        }

        updateFPS()

        classifyContacts()

        guard steeringContacts.count == 2 else {

            steeringIDs.removeAll()
            startX = nil

            lastHapticStep = nil
            lastEdge = 0

            previousSteering = 0

            publish(
                steering: 0,
                velocity: 0
            )

            return
        }


        let centerX =
            (
                steeringContacts[0].x +
                steeringContacts[1].x
            ) / 2.0


        guard let startX else {

            self.startX = centerX

            previousTimestamp =
                CFAbsoluteTimeGetCurrent()

            previousSteering = 0

            publish(
                steering: 0,
                velocity: 0
            )

            return
        }


        let displacement =
            centerX - startX


        let normalized = max(
            -1,
            min(
                1,
                displacement /
                    configuration.travelForFullLock
            )
        )


        let angle =
            normalized *
            configuration.maximumAngleDegrees


        let now =
            CFAbsoluteTimeGetCurrent()

        let dt = max(
            now - previousTimestamp,
            0.0001
        )

        let velocity =
            (normalized - previousSteering) / dt


        previousTimestamp = now
        previousSteering = normalized


        if configuration.hapticsEnabled {
            updateHaptics(for: angle)
        }


        publish(
            steering: normalized,
            velocity: velocity
        )
    }


    // MARK: - Contact classification

    private func classifyContacts() {

        let idsStillPresent =
            Set(contacts.map(\.id))

        steeringIDs =
            steeringIDs.intersection(idsStillPresent)


        // Сохраняем уже выбранные steering fingers.
        var steering = contacts.filter {
            steeringIDs.contains($0.id)
        }


        // Если steering pair ещё не сформирована,
        // выбираем два контакта, которые НЕ находятся
        // в brake zone.
        if steering.count != 2 {

            let candidates = contacts
                .filter {
                    !isInsideBrakeZone($0)
                }
                .sorted {
                    $0.x < $1.x
                }

            if candidates.count >= 2 {

                steering =
                    Array(candidates.prefix(2))

                steeringIDs =
                    Set(steering.map(\.id))
            } else {

                steering = []
                steeringIDs.removeAll()
            }
        }


        steeringContacts =
            steering.sorted {
                $0.x < $1.x
            }


        // Любой НЕ steering contact внутри
        // brake-zone может быть тормозом.
        brakeContact = contacts
            .filter {
                !steeringIDs.contains($0.id)
            }
            .filter {
                isInsideBrakeZone($0)
            }
            .max {
                $0.pressure < $1.pressure
            }
    }


    private func isInsideBrakeZone(
        _ contact: SteeringContact
    ) -> Bool {

        contact.x <=
            configuration.brakeZoneMaxX
        &&
        contact.y <=
            configuration.brakeZoneMaxY
    }


    // MARK: - Pedals

    private func throttleRawPressure() -> Double {

        // GAS:
        // отдельный палец в нижней левой pedal-zone.
        brakeContact?.pressure ?? 0
    }


    private func brakeRawPressure() -> Double {

        // BRAKE:
        // сильное одновременное давление двух
        // пальцев, которыми мы управляем рулём.
        guard steeringContacts.count == 2 else {
            return 0
        }

        return (
            steeringContacts[0].pressure +
            steeringContacts[1].pressure
        ) / 2.0
    }


    private func normalizePressure(
        _ value: Double,
        min minimum: Double,
        max maximum: Double
    ) -> Double {

        guard maximum > minimum else {
            return 0
        }

        return Swift.max(
            0,
            Swift.min(
                1,
                (value - minimum) /
                (maximum - minimum)
            )
        )
    }


    private func throttleValue() -> Double {

        normalizePressure(
            throttleRawPressure(),
            min:
                configuration
                    .throttlePressureMin,
            max:
                configuration
                    .throttlePressureMax
        )
    }


    private func brakeValue() -> Double {

        normalizePressure(
            brakeRawPressure(),
            min:
                configuration
                    .brakePressureMin,
            max:
                configuration
                    .brakePressureMax
        )
    }


    // MARK: - Publish

    private func publish(
        steering: Double,
        velocity: Double
    ) {

        let throttlePressure =
            throttleRawPressure()

        let brakePressure =
            brakeRawPressure()

        let throttle =
            throttleValue()

        let brake =
            brakeValue()


        let newState = SteeringState(

            steering: steering,

            angleDegrees:
                steering *
                configuration.maximumAngleDegrees,

            velocity: velocity,

            throttle: throttle,

            brake: brake,

            throttlePressure:
                throttlePressure,

            brakePressure:
                brakePressure,

            pressure:
                throttlePressure,

            isActive:
                steeringContacts.count == 2,

            isThrottleActive:
                throttle > 0,

            isBrakeActive:
                brake > 0,

            contactCount:
                contacts.count
        )


        state = newState


        for continuation
            in continuations.values
        {
            continuation.yield(newState)
        }
    }


    // MARK: - Reset

    private func reset() {

        startX = nil

        contacts = []

        steeringContacts = []

        steeringIDs.removeAll()

        brakeContact = nil

        lastHapticStep = nil

        lastEdge = 0

        previousSteering = 0

        state = .idle
    }


    // MARK: - Haptics

    private func updateHaptics(
        for angle: Double
    ) {

        guard let actuator =
            hapticActuator
        else {
            return
        }


        let maxAngle =
            configuration.maximumAngleDegrees

        let absoluteAngle =
            abs(angle)


        let edge: Int


        if angle >= maxAngle - 1 {

            edge = 1

        } else if angle <= -maxAngle + 1 {

            edge = -1

        } else {

            edge = 0
        }


        if edge != 0 &&
            edge != lastEdge
        {

            _ = actuator.actuate(
                pattern: .firmStrong,
                intensity: 1.0
            )

            lastEdge = edge

            lastHapticStep =
                Int(
                    round(
                        angle /
                        configuration
                            .hapticStepDegrees
                    )
                )

            return
        }


        if edge == 0 {
            lastEdge = 0
        }


        let step =
            Int(
                round(
                    angle /
                    configuration
                        .hapticStepDegrees
                )
            )


        guard step != lastHapticStep
        else {
            return
        }


        guard lastHapticStep != nil
        else {

            lastHapticStep = step
            return
        }


        lastHapticStep = step


        let proximity =
            min(
                absoluteAngle /
                maxAngle,
                1
            )


        let pattern: MTFeedbackPattern

        let intensity: Float


        switch proximity {

        case 0..<0.33:

            pattern = .light
            intensity = 0.18

        case 0.33..<0.67:

            pattern = .light
            intensity = 0.28

        case 0.67..<0.84:

            pattern = .medium
            intensity = 0.38

        case 0.84..<0.95:

            pattern = .mediumStrong
            intensity = 0.52

        default:

            pattern = .firm
            intensity = 0.70
        }


        _ = actuator.actuate(
            pattern: pattern,
            intensity: intensity
        )
    }


    // MARK: - FPS

    private func updateFPS() {

        frameCounter += 1

        let now =
            CFAbsoluteTimeGetCurrent()

        let elapsed =
            now - fpsStart


        if elapsed >= 0.5 {

            telemetryFPS =
                Double(frameCounter) /
                elapsed

            frameCounter = 0

            fpsStart = now
        }
    }
}
