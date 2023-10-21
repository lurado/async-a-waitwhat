//
//  ActorViewController.swift
//  AsyncAwait
//
//  Created by Sebastian Ludwig on 21.10.23.
//

import UIKit

func printEmptyLine(delay: Double = 0.1) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        print()
    }
}

actor ActorWorker: TaskSimulator {
    func blockingCompute(id: Int, seconds: TimeInterval) {
        let logger = Logger(id: id)
        logger.log("🟢 blockingCompute start")
        compute(logger: logger, seconds: seconds)
        logger.log("🛑 blockingCompute end")
    }
    
    func blockingCompute2(id: Int, seconds: TimeInterval) {
        let logger = Logger(id: id)
        logger.log("🟢 blockingCompute2 start")
        compute(logger: logger, seconds: seconds)
        logger.log("🛑 blockingCompute2 end")
    }
    
    func asyncComputeAndAwait(id: Int, computeSeconds: TimeInterval, sleepSeconds: UInt) async throws {
        let logger = Logger(id: id)
        logger.log("🟢 asyncOnWorkerSleep start")
        compute(logger: logger, seconds: computeSeconds)
        logger.log("🥱 asyncOnWorkerSleep await")
        try await taskSleep(seconds: sleepSeconds)
        logger.log("🛑 asyncOnWorkerSleep end")
    }
    
    func log(id: Int, _ message: String) {
        let logger = Logger(id: id)
        logger.log(message)
    }
}

class ActorViewController: UIViewController {
    @IBOutlet var buttonStackView: UIStackView!
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // fix the button's tint m(
        buttonStackView.arrangedSubviews.forEach { view in
            if let button = view as? UIButton {
                button.isEnabled = false
                button.isEnabled = true
            }
        }
    }
    
    // MARK: Actions
    
    let logger = Logger(id: 0)
    
    // Start two task right after another on an actor, which computes something
    // -> second task starts after the first one finished ✅ (expected)
    @IBAction func asyncBlockingCompute() {
        let actor = ActorWorker()
        
        Task {
            await actor.blockingCompute(id: 0, seconds: 2)
        }
        Task {
            await actor.blockingCompute(id: 1, seconds: 2)
        }
        
        printEmptyLine(delay: 8)
    }
    
    // Two different tasks on the same actor
    // -> second task starts after the first one finished ✅ (expected)
    // -> order of tasks may vary! ⚠️
    @IBAction func asyncBlockingComputeDifferentTasks() {
        let actor = ActorWorker()
        
        Task {
            await actor.blockingCompute(id: 0, seconds: 2)
        }
        Task {
            await actor.blockingCompute2(id: 1, seconds: 2)
        }
        
        printEmptyLine(delay: 8)
    }
    
    // Two times the same task, but on two different actors
    // -> both tasks run in parallel ✅ (expected, because "only one at a time" only applies _per instance_)
    @IBAction func asyncBlockingComputeTwoActors() {
        let actor1 = ActorWorker()
        let actor2 = ActorWorker()
        
        Task {
            await actor1.blockingCompute(id: 0, seconds: 2)
        }
        Task {
            await actor2.blockingCompute(id: 1, seconds: 2)
        }
        
        printEmptyLine(delay: 8)
    }
    
    // Variation of the first scenario: Two tasks on one actor, but the method contains `await`
    // -> second task starts immediately after the first one awaits ⚠️
    @IBAction func asyncComputeAndAwait() {
        let actor = ActorWorker()
        
        Task {
            try await actor.asyncComputeAndAwait(id: 0, computeSeconds: 2, sleepSeconds: 1)
        }
        Task {
            try await actor.asyncComputeAndAwait(id: 1, computeSeconds: 2, sleepSeconds: 1)
        }
        
        printEmptyLine(delay: 8)
    }
}
