package coro;

class CoroutineIntrinsics {
    public static macro function currentCompletion():haxe.macro.Expr {
        return macro _hx_completion;
    }
}