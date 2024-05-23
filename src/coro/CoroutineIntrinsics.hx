package coro;

class CoroutineIntrinsics {
    public static macro function currentContinuation():haxe.macro.Expr {
        return macro _hx_continuation;
    }

    public static macro function isCancellationRequested():haxe.macro.Expr {
        return macro _hx_continuation._hx_context.token.isCancellationRequested;
    }
}