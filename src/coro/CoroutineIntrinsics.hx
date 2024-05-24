package coro;

class CoroutineIntrinsics {
    public static macro function currentContinuation():haxe.macro.Expr {
        return macro _hx_continuation;
    }

    public static macro function create(f:haxe.macro.Expr, a:Array<haxe.macro.Expr>):haxe.macro.Expr {
        return switch f.expr {
            case EConst(CIdent(func)):
                final tp = { pack: [], name: 'HxCoro_$func' };

                return macro new $tp($a{ a });
            case EMeta({ name: ":suspend" }, { expr: EFunction(kind, f) }):
                return macro null;
            case _:
                haxe.macro.Context.error("Unsupported Expression", haxe.macro.Context.currentPos());
        }
    }

    public static macro function isCancellationRequested():haxe.macro.Expr {
        return macro _hx_continuation._hx_context.token.isCancellationRequested;
    }
}