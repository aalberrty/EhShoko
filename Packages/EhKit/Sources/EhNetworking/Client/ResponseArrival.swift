/// Tells whoever started a client operation the moment each of its requests is answered,
/// before the answer is parsed.
///
/// The timings of the performance budgets need it ("rows on screen within 150 ms of the
/// response"): a model binds `observer` around its call into `EhClient`, and `EhClient.send`
/// calls it once per answered request, on the client's executor. It travels with the task,
/// like `OperationTrace`, so no operation's signature changes; nothing is bound outside a
/// measured load, and then a send pays one task-local read.
public enum ResponseArrival {
    @TaskLocal public static var observer: (@Sendable () -> Void)?
}
