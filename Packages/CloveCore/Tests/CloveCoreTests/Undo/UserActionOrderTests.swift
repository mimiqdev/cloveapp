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
            guard await order.start(ticket) else { return }
            log.append(ticket)
        }
    }

    /// The tickets that reached ``UserActionOrder/start(_:)``, in order.
    final class Log {
        private(set) var tickets: [Int] = []
        func append(_ ticket: Int) { tickets.append(ticket) }
    }

    /// Lets the main actor run parked tasks until the log holds `count` tickets, bounded.
    private func waitForTickets(_ count: Int, in log: Log) async {
        for _ in 0..<200 where log.tickets.count < count {
            await Task.yield()
        }
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
        let before = order.reserve(.action)
        let step = order.reserve(.step)
        let after = order.reserve(.action)

        let runningStep = startInBackground(order, step, into: log)
        let runningAfter = startInBackground(order, after, into: log)
        await Task.yield()
        // The step waits for the action before it to start, which has not run yet.
        #expect(log.tickets.isEmpty)

        let runningBefore = startInBackground(order, before, into: log)
        await waitForTickets(2, in: log)
        #expect(log.tickets == [before, step])

        order.finishStep(step)
        _ = await (runningBefore.value, runningStep.value, runningAfter.value)
        #expect(log.tickets == [before, step, after])
    }

    @Test func aCancelledTicketDoesNotStart() async {
        let order = UserActionOrder()
        let cancelled = order.reserve(.action)
        order.cancel(cancelled)
        #expect(await order.start(cancelled) == false)
        #expect(await order.start(9999) == false)
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
        await waitForTickets(1, in: log)
        #expect(log.tickets == [runningStep])

        order.finishStep(runningStep)
        await waitForTickets(3, in: log)
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
        await waitForTickets(1, in: log)
        #expect(log.tickets == [first])

        order.finishStep(first)
        await waitForTickets(2, in: log)
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
        guard await order.start(tap) else { return }
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

        _ = await order.start(action)
        await Task.yield()
        // The step starts once the earlier action started, and ends when the caller finishes it.
        order.finishStep(step)
        _ = await stepTask.value
        #expect(log.tickets == [step])
    }
}
