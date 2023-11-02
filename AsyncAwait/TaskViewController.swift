//
//  TaskViewController.swift
//  AsyncAwait
//
//  Created by Sebastian Ludwig on 21.10.23.
//

import UIKit

extension Task where Success == Never, Failure == Never  {
    static func sleep(seconds: TimeInterval) async throws {
        try await sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

protocol Logging {
    var logger: Logger { get }
}

protocol WorkSimulator {
    func blockingCompute(logger: Logger, seconds: TimeInterval)
}

extension WorkSimulator {
    func blockingCompute(logger: Logger, seconds: TimeInterval) {
        logger.log("⚙️ computing")
        let start = Date().timeIntervalSince1970
        var iteration = 1
        while Date().timeIntervalSince1970 - start < seconds {
            sqrt(pow(Double.pi, Double(iteration)))
            iteration += 1
        }
    }
}

extension WorkSimulator where Self: Logging {
    func blockingCompute(seconds: TimeInterval) {
        blockingCompute(logger: logger, seconds: seconds)
    }
}

struct Worker: WorkSimulator, Logging {
    let logger: Logger
    let id: Int
    
    init(id: Int) {
        self.id = id
        logger = Logger(id: id)
    }
    
    func asyncTaskSleep(seconds: TimeInterval) async throws {
        logger.log("🟢 Worker asyncTaskSleep start")
        try await Task.sleep(seconds: seconds)
        logger.log("🛑 Worker asyncTaskSleep end")
    }
    
    func asyncBlockingCompute(seconds: TimeInterval) async {
        logger.log("🟢 Worker asyncBlockingCompute start")
        blockingCompute(seconds: seconds)
        logger.log("🛑 Worker asyncBlockingCompute end")
    }
    

    func asyncDispatchCompute(seconds: TimeInterval, queuePriority: DispatchQoS.QoSClass) async throws {
        logger.log("🟢 Worker asyncDispatchCompute start")
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: queuePriority).async {
                self.blockingCompute(seconds: seconds)
                continuation.resume()
            }
        }
        logger.log("🛑 Worker asyncDispatchCompute end")
    }
}

class TaskViewController: UIViewController, WorkSimulator, Logging {
    let logger = Logger(id: 0)
    
    @IBOutlet private var taskPriorityButtons: [UIButton]!
    @IBOutlet private var queuePriorityButtons: [UIButton]!
    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var taskCountLabel: UILabel!
    @IBOutlet private var taskCountStepper: UIStepper!
    
    @IBOutlet private var taskCountConfigurationView: UIView!
    @IBOutlet private var queuePriorityConfigurationView: UIView!
    
    @IBAction private func changeTaskPriority(_ sender: UIButton) {
        taskPriorityButtons.forEach { $0.isSelected = false }
        sender.isSelected = true
    }
    
    @IBAction private func changeQueuePriority(_ sender: UIButton) {
        queuePriorityButtons.forEach { $0.isSelected = false }
        sender.isSelected = true
    }
    
    @IBAction private func changeTaskCount(_ sender: UIStepper) {
        taskCountLabel.text = Int(sender.value).description
    }
    
    private var taskPriority: TaskPriority {
        let selectedButton = taskPriorityButtons.first { $0.isSelected }!
        return TaskPriority(rawValue: UInt8(selectedButton.tag))
    }
    
    private var queuePriority: DispatchQoS.QoSClass {
        let selectedButton = queuePriorityButtons.first { $0.isSelected }!
        return DispatchQoS.QoSClass(rawValue: qos_class_t(rawValue: UInt32(selectedButton.tag)))!
    }
    
    private var taskCount: Int {
        Int(taskCountStepper.value)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scrollViewDidScroll(scrollView)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.flashScrollIndicators()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        taskCountStepper.value = 2
    }
}

extension TaskViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentPageIndex = Int(round(scrollView.contentOffset.x/view.frame.width))
        
        taskCountConfigurationView.isHidden = currentPageIndex < 6
        queuePriorityConfigurationView.isHidden = currentPageIndex < 7
    }
}

extension TaskViewController {
    
    // MARK: - Inline Task
    // Start a Task, which sleeps for X seconds
    // -> always run on main thread ✅ (expected)
    // -> taskPriority does NOT matter ⚠️ (kind of expected, because the first point was expected)
    
    @IBAction private func inlineTask() {
        Task(priority: taskPriority) {
            logger.log("🟢 inlineTask start")
            try await Task.sleep(seconds: 3)
            logger.log("🛑 inlineTask end")
        }
    }
    
    // MARK: - Inline Task.detached
    // Same, but detached Task
    // -> taskPriority matters ✅
    
    @IBAction private func inlineTaskDetached() {
        Task.detached(priority: taskPriority) {
            self.logger.log("🟢 inlineTaskDetached start")
            try await Task.sleep(seconds: 3)
            self.logger.log("🛑 inlineTaskDetached end")
        }
    }
    
    // MARK: - Async sleep on ViewController
    // Extraction of the code from inside the `Task {}` block into a method
    // -> _always_ run on main thread 🚨 (because `UIViewController` is annotated with `@MainActor`)
    
    func asyncTaskSleep(seconds: TimeInterval) async throws {
        self.logger.log("🟢 VC asyncTaskSleep start")
        try await Task.sleep(seconds: seconds)
        self.logger.log("🛑 VC asyncTaskSleep end")
    }
    
    @IBAction private func asyncTaskSleepOnViewController() {
        Task.detached(priority: taskPriority) {
            try await self.asyncTaskSleep(seconds: 3)
        }
    }
    
    // MARK: - Async sleep on Worker
    // Same code, but extracted into another class (Worker)
    // -> run on the specified queue ✅
    // -> BTW, non-detached behaves the same
    
    @IBAction private func asyncTaskSleepOnWorker() {
        Task.detached(priority: taskPriority) {
            let worker = Worker(id: 1)
            try await worker.asyncTaskSleep(seconds: 3)
        }
    }
    
    // MARK: - Async blocking compute on ViewController
    // Why is this difference important? Because:
    //     "async functions must never block"
    //         Apple
    //
    // Don't use Task.sleep (which yields), but `blockingCompute` to block
    // the thread, simulating e.g. a long running non-`async` function (network call,
    // computation, ...)
    // -> UI not responsive ⚠️ (expected, but needs to be avoided!)
    
    func asyncBlockingCompute(seconds: TimeInterval) async throws {
        logger.log("🟢 VC asyncBlockingCompute start")
        blockingCompute(seconds: seconds)
        logger.log("🛑 VC asyncBlockingCompute end")
    }
    
    @IBAction private func asyncBlockingComputeOnViewController() {
        Task.detached(priority: taskPriority) {
            try await self.asyncBlockingCompute(seconds: 3)
        }
    }
    
    // MARK: - Async blocking compute on Worker
    // Same blocking task, but run on a Worker (not the main thread)
    // -> UI stays responsive ✅
    
    @IBAction private func asyncBlockingComputeOnWorker() {
        Task.detached(priority: taskPriority) {
            let worker = Worker(id: 1)
            await worker.asyncBlockingCompute(seconds: 3)
        }
    }
    
    // MARK: - Many Workers blocking compute
    // Start more than one blocking task
    // iOS 15 Simulator:
    // -> No parallelism. The next task is only started after the previous completed 🤯
    // iOS 16 Simulator & Device:
    // -> Parrallelism, but the max number of parallel tasks (of a given priority)  ⚠️
    //    is limited (~6)
    // -> The rest doesn't even start. All other async tasks in the system are blocked, 🚨
    //    until one Swift Concurrency thread is available again!
    // -> "async functions must _never_ block" ⚠️
    // Fun fact:
    // -> Running the app on macOS (M1) behaves like an iOS Device
    
    @IBAction private func manyAsyncBlockingComputeOnWorker() {
        for i in 0..<taskCount {
            Task.detached(priority: taskPriority) {
                let worker = Worker(id: i + 1)
                await worker.asyncBlockingCompute(seconds: 3)
            }
        }
        Task.detached(priority: taskPriority) {
            self.logger.log("⚠️ inlined task")
        }
    }
    
    // MARK: - Many Workers blocking compute dispatched
    // Dispatch long running tasks to GCD queues to free up Swift Concurrency threads
    // -> Other tasks are started immediately and can be run in parallel ✅
    // -> Yaaay! But we're back in the world of GCD where we have to worry about thread
    //    explosion and synchronization :-/
    
    @IBAction private func manyAsyncDispatchBlockingComputeOnWorker() {
        for i in 0...taskCount {
            Task.detached(priority: taskPriority) { [queuePriority] in
                let worker = Worker(id: i + 1)
                try await worker.asyncDispatchCompute(
                    seconds: 3,
                    queuePriority: queuePriority
                )
            }
        }
        Task.detached(priority: taskPriority) {
            self.logger.log("⚠️ inlined task")
        }
    }
    
    // MARK: - The End
}
