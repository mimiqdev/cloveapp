import Testing

import CloveCore

/// The order user actions start in: their arrival order, with steps finishing first
/// (PRD P0-05's Undo row).
@Suite(.timeLimit(.minutes(1))) @MainActor struct UserActionOrderTests {
    /// Runs one ticket's start on its own task and records when it got through.
    private func startInBackground(
        _ order: UserActionOrder, _ ticket: Int, into log: Log
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await order.start(ticket)
            log.append(ticket)
        }
    }

    /// The tickets that reached ``UserActionOrder/start(_:)``, in order.
    final class Log {
        private(set) var tickets: [Int] = []
        func append(_ ticket: Int) { tickets.append(ticket) }
    }

    @Test func actionsStartInArrivalOrderWhateverOrderTheirTasksRun() async {
        let order = UserActionOrder()
        let log = Log()
        let first = order.reserve(.action)
        let second = order.reserve(.action)
        let third = order.reserve(.action)

        // Their tasks are started out of order, which is what a burst of taps looks like.
        let runningThird = startInBackground(order, third, into: log)
        let runningSecond = startInBackground(order, second, into: log)
        let runningFirst = startInBackground(order, first, into: log)
        _ = await (runningFirst.value, runningSecond.value, runningThird.value)
        #expect(log.tickets == [first, second, third])
    }

    @Test func aStepRunsAfterTheActionBeforeItAndBeforeTheActionAfterIt() async {
        let order = UserActionOrder()
        let log = Log()
        let step = order.reserve(.step)
        let action = order.reserve(.action)

        let runningStep = startInBackground(order, step, into: log)
        let runningAction = startInBackground(order, action, into: log)
        await Task.yield()

        // The action waits for the step to finish; the step waits for nothing before it.
        #expect(log.tickets == [step])
        order.finishStep(step)
        _ = await (runningStep.value, runningAction.value)
        #expect(log.tickets == [step, action])
    }

    @Test func aTapAPressAndAnotherTapKeepTheOrder() async {
        // ⌘Z0 runs, the user taps ★3, presses ⌘Z1, then taps ★4. ⌘Z1 must undo ★3, not ★4.
        let order = UserActionOrder()
        let log = Log()
        let runningStep = order.reserve(.step)
        let tapOne = order.reserve(.action)
        let press = order.reserve(.step)
        let tapTwo = order.reserve(.action)

        let stepTask = startInBackground(order, runningStep, into: log)
        let tapOneTask = startInBackground(order, tapOne, into: log)
        let pressTask = startInBackground(order, press, into: log)
        let tapTwoTask = startInBackground(order, tapTwo, into: log)
        await Task.yield()
        #expect(log.tickets == [runningStep])

        order.finishStep(runningStep)
        await Task.yield()
        // ★3 started before the press, and ★4 waits for the press to finish.
        #expect(log.tickets == [runningStep, tapOne, press])
        order.finishStep(press)
        _ = await (stepTask.value, tapOneTask.value, pressTask.value, tapTwoTask.value)
        #expect(log.tickets == [runningStep, tapOne, press, tapTwo])
    }

    @Test func twoPressesBeforeATapRunBeforeIt() async {
        let order = UserActionOrder()
        let log = Log()
        let first = order.reserve(.step)
        let second = order.reserve(.step)
        let tap = order.reserve(.action)

        let firstTask = startInBackground(order, first, into: log)
        let secondTask = startInBackground(order, second, into: log)
        let tapTask = startInBackground(order, tap, into: log)
        await Task.yield()
        #expect(log.tickets == [first])

        order.finishStep(first)
        await Task.yield()
        #expect(log.tickets == [first, second])
        order.finishStep(second)
        _ = await (firstTask.value, secondTask.value, tapTask.value)
        #expect(log.tickets == [first, second, tap])
    }

    @Test func aCancelledTicketDoesNotHoldLaterActionsBack() async {
        let order = UserActionOrder()
        let log = Log()
        let cancelled = order.reserve(.step)
        let tap = order.reserve(.action)

        order.cancel(cancelled)
        await order.start(tap)
        log.append(tap)
        #expect(log.tickets == [tap])
    }

    @Test func aStepWaitsForAnEarlierActionToStart() async {
        let order = UserActionOrder()
        let log = Log()
        let action = order.reserve(.action)
        let step = order.reserve(.step)

        let stepTask = startInBackground(order, step, into: log)
        await Task.yield()
        #expect(log.tickets.isEmpty)

        await order.start(action)
        await Task.yield()
        // The step starts once the earlier action started, and ends when the caller finishes it.
        order.finishStep(step)
        _ = await stepTask.value
        #expect(log.tickets == [step])
    }
}
