import haxe.Exception;

interface IScheduler {
    function schedule(func:()->Void):Void;
}

class CancellationException extends Exception {
    public function new(message:String) {
        super(message);
    }
}

class CancellationTokenSource {
    var cancelled:Bool;

    final registrations:Array<()->Void>;

    public final token:CancellationToken;

    public var isCancellationRequested(get, never):Bool;

    public function get_isCancellationRequested() {
        return cancelled;
    }

    public function new() {
        token         = new CancellationToken(this);
        cancelled     = false;
        registrations = [];
    }

    public function register(func:()->Void) {
        if (isCancellationRequested) {
            throw new CancellationException('Cancellation token has already been cancelled');
        }

        registrations.push(func);
    }

    public function cancel() {
        if (isCancellationRequested) {
            throw new CancellationException('Cancellation token has already been cancelled');
        }

        cancelled = true;

        for (func in registrations) {
            func();
        }
    }
}

class CancellationToken {
    final source:CancellationTokenSource;

    public var isCancellationRequested(get, never):Bool;

    public function get_isCancellationRequested() {
        return source.isCancellationRequested;
    }

    public function new(source) {
        this.source = source;
    }

    public function register(func:()->Void) {
        source.register(func);
    }
}

class CoroutineContext {
    public final scheduler:IScheduler;

    public final token:CancellationToken;

    public function new(scheduler, token) {
        this.scheduler = scheduler;
        this.token     = token;
    }
}

interface IContinuation<T> {
    final _hx_context:CoroutineContext;

	function resume(result:T, error:Exception):Void;
}

class Coroutine {
    public static function suspend(func:(IContinuation<Any>)->Void, cont:IContinuation<Any>):CoroutineResult<Any> {
        cont._hx_context.scheduler.schedule(() -> {
            func(cont);
        });
	
		return Suspended;
    }

    public static macro function isCancellationRequested():haxe.macro.Expr.ExprOf<Bool> {
        return macro _hx_continuation._hx_context.token.isCancellationRequested;
    }
}

enum CoroutineResult<T> {
    Suspended;
    Success(v:T);
    Error(exn:Dynamic);
}