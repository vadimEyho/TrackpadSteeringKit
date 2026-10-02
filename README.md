# TrackpadSteeringKit

Экспериментальная Swift-библиотека, превращающая трекпад MacBook в игровой рулевой контроллер с тактильной отдачей.

## Что умеет

Два пальца работают как линейная рулевая рейка:

- свайп двумя пальцами влево → руль влево;
- свайп двумя пальцами вправо → руль вправо;
- нормализованный steering input от `-1.0` до `+1.0`;
- линейное и предсказуемое управление без acceleration curve;
- velocity рулевого ввода;
- pressure двух пальцев;
- recenter;
- raw telemetry контактов;
- haptic detent каждые 10°;
- усиление тактильной отдачи к границам;
- сильный физический отклик на full-lock;
- игровой код не зависит напрямую от Subsurface.

## Требования

- macOS 13+
- MacBook / Mac с совместимым Multi-Touch / Force Touch trackpad
- Swift 6.4+
- Swift Package Manager

## Установка через Swift Package Manager

Добавьте пакет:

```swift
dependencies: [
    .package(
        url: "https://github.com/vadimEyho/TrackpadSteeringKit.git",
        from: "0.1.0"
    )
]
```

И подключите продукт к target игры:

```swift
.target(
    name: "MyGame",
    dependencies: [
        .product(
            name: "TrackpadSteeringKit",
            package: "TrackpadSteeringKit"
        )
    ]
)
```

После этого:

```swift
import TrackpadSteeringKit
```

## Быстрый старт

```swift
import TrackpadSteeringKit

@MainActor
final class GameInput {

    private let steering = TrackpadSteeringController()

    func start() {
        steering.start()

        Task {
            for await state in steering.states() {
                updateCarSteering(state.steering)
            }
        }
    }

    private func updateCarSteering(_ value: Double) {
        // -1.0 = полный левый
        //  0.0 = центр
        // +1.0 = полный правый
    }
}
```

## SteeringState

Главное значение для игры:

```swift
state.steering
```

Диапазон:

```text
-1.0 ───────── 0.0 ───────── +1.0
 LEFT         CENTER          RIGHT
```

Дополнительно доступны:

```swift
state.angleDegrees
state.velocity
state.pressure
state.isActive
state.contactCount
```

### Пример игрового цикла

```swift
for await state in controller.states() {
    car.steeringInput = state.steering
}
```

Игра получает уже готовое нормализованное значение и не должна знать ничего о raw Multi-Touch API.

## Настройка

```swift
let controller = TrackpadSteeringController(
    configuration: SteeringConfiguration(
        travelForFullLock: 0.35,
        maximumAngleDegrees: 180,
        hapticStepDegrees: 10,
        hapticsEnabled: true
    )
)
```

### travelForFullLock

Расстояние свайпа по нормализованной ширине трекпада, необходимое для полного выворота.

```swift
travelForFullLock: 0.35
```

Меньше значение → более чувствительное управление.

Больше значение → для полного выворота требуется более длинный свайп.

### maximumAngleDegrees

Максимальный логический/визуальный угол руля:

```swift
maximumAngleDegrees: 180
```

Можно использовать другой диапазон, например:

```swift
maximumAngleDegrees: 540
```

При этом игровой steering по-прежнему остаётся нормализованным:

```text
-1.0 ... 0.0 ... +1.0
```

### hapticStepDegrees

Шаг тактильных насечек:

```swift
hapticStepDegrees: 10
```

При значении 10 трекпад создаёт физический haptic detent через каждые 10°.

Интенсивность автоматически увеличивается при приближении к full-lock.

### hapticsEnabled

```swift
hapticsEnabled: true
```

Полностью включает или отключает тактильную отдачу.

## Recenter

Текущую позицию двух пальцев можно принять за новый центр:

```swift
controller.recenter()
```

## Публичный протокол

Игровой код может зависеть не от конкретного Trackpad-контроллера, а от абстракции:

```swift
@MainActor
public protocol SteeringControllerProtocol: AnyObject {

    var state: SteeringState { get }

    var configuration: SteeringConfiguration { get set }

    func start()

    func stop()

    func recenter()
}
```

Например:

```swift
let steeringController: any SteeringControllerProtocol
```

Это позволяет позже заменить источник управления без изменения игровой физики.

## Архитектура

```text
MacBook Trackpad
       │
       ▼
   Subsurface
       │
       ▼
TrackpadSteeringController
       │
       ▼
SteeringControllerProtocol
       │
       ▼
      Game
```

В будущем можно реализовать тот же протокол для других устройств:

```text
TrackpadSteeringController
PhysicalWheelController
GameControllerSteeringController
iPhoneSteeringController
```

Для игры они будут выглядеть одинаково:

```swift
state.steering
```

## Как работает управление

При появлении двух активных контактов библиотека запоминает среднюю X-координату пальцев как центр.

Дальше вычисляется горизонтальное смещение:

```text
LEFT  ← ←  [ finger ] [ finger ]  → →  RIGHT
```

Расстояние между пальцами и их вращение не используются.

Поэтому управление остаётся линейным и предсказуемым.

Когда два пальца перестают быть активными, steering возвращается в нейтральное состояние.

## Haptics

Тактильная отдача генерируется непосредственно Force Touch trackpad.

По умолчанию:

```text
CENTER
  │
  ├── лёгкие detents
  │
  ├── средние detents
  │
  ├── сильные detents
  │
  └── FULL LOCK → сильный физический упор
```

Интенсивность зависит от близости к максимальному углу.

## Важно

TrackpadSteeringKit использует [Subsurface](https://github.com/mrkai77/Subsurface), который работает с приватным macOS `MultitouchSupport.framework`.

Это означает, что библиотека предназначена прежде всего для:

- экспериментов;
- прототипов;
- локальных macOS-игр;
- исследований альтернативных игровых контроллеров.

Private API может измениться в будущих версиях macOS и может быть несовместим с требованиями Mac App Store.

## Статус

### 0.1.0

Первая экспериментальная версия:

- Multi-Touch input
- two-finger swipe steering
- linear steering
- `-1...+1` normalized input
- steering velocity
- pressure
- telemetry
- recenter
- AsyncStream API
- haptic detents
- progressive haptic resistance near full-lock

## License

Experimental project. License will be specified separately.
