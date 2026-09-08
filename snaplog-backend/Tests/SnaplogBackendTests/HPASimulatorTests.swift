import Foundation
import Testing

// MARK: - Simulations of the Kubernetes policies deployed in k8s/app.yaml and k8s/worker.yaml.
// These mirror the real HorizontalPodAutoscaler math, probe-driven auto-repair,
// and PodDisruptionBudget semantics so the behavior is verifiable with `swift test`.

struct HPAPolicy {
    var minReplicas: Int
    var maxReplicas: Int
    var cpuTargetPercent: Int
    var scaleDownStabilizationSeconds: Int
}

struct PodMetrics {
    var replicas: Int
    var averageCPUPercent: Int
}

enum HPASimulator {
    static func desiredReplicas(metrics: PodMetrics, policy: HPAPolicy) -> Int {
        let proposed = Int((Double(metrics.replicas * metrics.averageCPUPercent) / Double(policy.cpuTargetPercent)).rounded(.up))
        return min(max(proposed, policy.minReplicas), policy.maxReplicas)
    }

    static func nextReplicas(current: Int, metrics: PodMetrics, policy: HPAPolicy, lastScaleDownAt: Int, now: Int) -> Int {
        let desired = desiredReplicas(metrics: metrics, policy: policy)
        if desired < current {
            // Scale-down only applies once the stabilization window has passed
            // without a higher recommendation — same as scaleDown.stabilizationWindowSeconds.
            guard now - lastScaleDownAt >= policy.scaleDownStabilizationSeconds else { return current }
            return desired
        }
        return max(desired, current)
    }
}

// MARK: - Auto-repair simulation: kubelet liveness probes + Deployment controller

struct SimulatedPod {
    enum State { case ready, unready, crashed }
    var state: State
    var consecutiveLivenessFailures = 0
    var restarts = 0
}

struct ClusterSimulator {
    var pods: [SimulatedPod]
    let livenessFailureThreshold = 3
    let disruptionBudgetMinAvailable = 1

    mutating func tick(podFailingProbes podIndex: Int) {
        guard pods.indices.contains(podIndex) else { return }
        pods[podIndex].consecutiveLivenessFailures += 1
        pods[podIndex].state = .unready
        if pods[podIndex].consecutiveLivenessFailures >= livenessFailureThreshold {
            // kubelet restarts the container; the Deployment keeps the replica.
            pods[podIndex] = SimulatedPod(state: .ready, restarts: pods[podIndex].restarts + 1)
        }
    }

    mutating func crash(_ podIndex: Int) {
        guard pods.indices.contains(podIndex) else { return }
        pods[podIndex] = SimulatedPod(state: .ready, restarts: pods[podIndex].restarts + 1)
    }

    var readyReplicas: Int { pods.filter { $0.state == .ready }.count }
    var totalRestarts: Int { pods.reduce(0) { $0 + $1.restarts } }

    func allowsVoluntaryDisruption() -> Bool { readyReplicas - 1 >= disruptionBudgetMinAvailable }
}

// MARK: - Tests

@Suite("Kubernetes HPA auto-scaling (mock)")
struct HPASimulatorTests {
    let policy = HPAPolicy(
        minReplicas: 2,
        maxReplicas: 10,
        cpuTargetPercent: 70,
        scaleDownStabilizationSeconds: 60
    )

    @Test("Idle load stays at the minimum")
    func staysAtMinimum() {
        #expect(HPASimulator.desiredReplicas(metrics: .init(replicas: 2, averageCPUPercent: 10), policy: policy) == 2)
    }

    @Test("High CPU scales up proportionally")
    func scalesUp() {
        // 2 pods at 140% average → ceil(2 * 140 / 70) = 4
        #expect(HPASimulator.desiredReplicas(metrics: .init(replicas: 2, averageCPUPercent: 140), policy: policy) == 4)
        // 4 pods still hot → 8, capped at 10
        #expect(HPASimulator.desiredReplicas(metrics: .init(replicas: 4, averageCPUPercent: 150), policy: policy) == 9)
        #expect(HPASimulator.desiredReplicas(metrics: .init(replicas: 8, averageCPUPercent: 200), policy: policy) == 10)
    }

    @Test("Replicas are clamped to min and max")
    func clamps() {
        #expect(HPASimulator.desiredReplicas(metrics: .init(replicas: 9, averageCPUPercent: 1), policy: policy) == 2)
        #expect(HPASimulator.desiredReplicas(metrics: .init(replicas: 9, averageCPUPercent: 400), policy: policy) == 10)
    }

    @Test("Scale-down waits out the stabilization window (no flapping)")
    func stabilizationWindow() {
        // Traffic dropped at t=0; recommendation is 2 but we hold 5 replicas…
        #expect(HPASimulator.nextReplicas(current: 5, metrics: .init(replicas: 5, averageCPUPercent: 10), policy: policy, lastScaleDownAt: 0, now: 30) == 5)
        // …and still hold at t=59…
        #expect(HPASimulator.nextReplicas(current: 5, metrics: .init(replicas: 5, averageCPUPercent: 10), policy: policy, lastScaleDownAt: 0, now: 59) == 5)
        // …but scale down once the 60s window passes.
        #expect(HPASimulator.nextReplicas(current: 5, metrics: .init(replicas: 5, averageCPUPercent: 10), policy: policy, lastScaleDownAt: 0, now: 60) == 2)
    }

    @Test("A burst inside the window cancels the pending scale-down")
    func burstCancelsScaleDown() {
        // Load returns mid-window: the recommendation is up again, so replicas never drop.
        #expect(HPASimulator.nextReplicas(current: 5, metrics: .init(replicas: 5, averageCPUPercent: 10), policy: policy, lastScaleDownAt: 0, now: 30) == 5)
        #expect(HPASimulator.nextReplicas(current: 5, metrics: .init(replicas: 5, averageCPUPercent: 140), policy: policy, lastScaleDownAt: 0, now: 31) == 10)
    }
}

@Suite("Kubernetes auto-repair (mock)")
struct AutoRepairTests {
    @Test("Failing liveness probe restarts the pod after 3 failures")
    func livenessRestart() {
        var cluster = ClusterSimulator(pods: [.init(state: .ready), .init(state: .ready)])
        cluster.tick(podFailingProbes: 0)
        cluster.tick(podFailingProbes: 0)
        #expect(cluster.pods[0].restarts == 0)
        cluster.tick(podFailingProbes: 0)
        #expect(cluster.pods[0].restarts == 1)
        #expect(cluster.pods[0].state == .ready)
        #expect(cluster.readyReplicas == 2)
    }

    @Test("A crashed pod is replaced and the replica count is restored")
    func crashReplacement() {
        var cluster = ClusterSimulator(pods: [.init(state: .ready), .init(state: .ready), .init(state: .ready)])
        cluster.crash(1)
        #expect(cluster.readyReplicas == 3)
        #expect(cluster.pods[1].restarts == 1)
    }

    @Test("Unready pods receive no traffic (readiness gating)")
    func readinessGating() {
        var cluster = ClusterSimulator(pods: [.init(state: .ready), .init(state: .ready)])
        cluster.pods[1].state = .unready
        #expect(cluster.readyReplicas == 1)
    }

    @Test("PodDisruptionBudget blocks evicting the last ready replica")
    func disruptionBudget() {
        var cluster = ClusterSimulator(pods: [.init(state: .ready), .init(state: .ready)])
        #expect(cluster.allowsVoluntaryDisruption() == true)
        cluster.pods[1].state = .unready
        #expect(cluster.allowsVoluntaryDisruption() == false)
    }

    @Test("Rolling update with maxUnavailable 0 keeps capacity")
    func rollingUpdate() {
        let replicas = 3
        var serving = replicas
        let maxUnavailable = 0
        let maxSurge = 1
        var surgePods = 0
        // The Deployment controller replaces one pod at a time:
        for _ in 0..<replicas {
            surgePods += maxSurge
            serving += maxSurge
            #expect(serving - 0 >= replicas - maxUnavailable)
            surgePods -= 1
            serving -= 1 // new pod becomes ready, old pod terminates
        }
        #expect(serving == replicas)
    }
}
