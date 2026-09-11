import CoreMotion
import Observation
import UIKit

@MainActor
@Observable
final class RotationDetector {

    private(set) var isLandscape = false

    @ObservationIgnored private let motionManager = CMMotionManager()
    @ObservationIgnored private var deviceObserver: NSObjectProtocol?
    @ObservationIgnored private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let gravity = motion?.gravity else { return }
                let sideways = abs(gravity.x) > 0.75 && abs(gravity.x) > abs(gravity.y)
                if sideways != self.isLandscape {
                    self.isLandscape = sideways
                }
            }
        } else {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            let update: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                let sideways = UIDevice.current.orientation.isLandscape
                if sideways != self.isLandscape {
                    self.isLandscape = sideways
                }
            }
            deviceObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in update() }
            }
            update()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
            deviceObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        isLandscape = false
    }
}
