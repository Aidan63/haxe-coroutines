package coro;

class CoroutineIntrinsics {
    public static macro function currentCompletion():haxe.macro.Expr {
        return macro _hx_completion;
    }

    public static macro function isCancellationRequested():haxe.macro.Expr {
        return macro _hx_completion._hx_context.token.isCancellationRequested;
    }
}