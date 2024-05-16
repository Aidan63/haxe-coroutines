import sys.thread.Mutex;
import haxe.exceptions.NotImplementedException;
import haxe.Exception;
import haxe.atomic.AtomicObject;

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
        final safe = new SafeContinuation(cont);

        func(safe);
	
		return safe.get();
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

class SafeContinuation implements IContinuation<Any> {
    final _hx_completion:IContinuation<Any>;
    
    final lock:Mutex;

    var state:Null<CoroutineResult<Any>>;

	public final _hx_context:CoroutineContext;

    public function new(completion) {
        _hx_completion = completion;
        _hx_context    = _hx_completion._hx_context;
        lock           = new Mutex();
        state          = null;
    }

    public function resume(result:Any, error:Exception) {
        _hx_context.scheduler.schedule(() -> {
            lock.acquire();

            switch state {
                case null:
                    switch error {
                        case null:
                            state = Success(result);
                        case exn:
                            state = Error(exn);
                    }
                    lock.release();
                case _:
                    lock.release();
    
                    _hx_completion.resume(result, error);
            } 
        });
    }

    public function get():CoroutineResult<Any> {
        lock.acquire();

        var result = switch state {
            case Success(v):
                Success(v);
            case Error(exn):
                Error(exn);
            case _:
                state = Suspended;
        }

        lock.release();

        return result;
    }
}