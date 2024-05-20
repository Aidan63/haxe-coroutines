import coro.Primitive;
import coro.schedulers.IScheduler;
import coro.schedulers.EventLoopScheduler;
import sys.thread.Thread;
import sys.thread.Mutex;
import haxe.Exception;

class CancellationException extends Exception {
    public function new(message:String) {
        super(message);
    }
}

abstract Registration(()->Void) {
    public function new(func:()->Void) {
        this = func;
    }

    public function unregister() {
        this();
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

    public function register(func:()->Void):Registration {
        if (isCancellationRequested) {
            throw new CancellationException('Cancellation token has already been cancelled');
        }

        registrations.push(func);

        return new Registration(() -> registrations.remove(func));
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

    public function register(func:()->Void):Registration {
        return source.register(func);
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
    public static inline function suspend(func:(IContinuation<Any>)->Void, _hx_continuation:IContinuation<Any>):Any {
        final safe = new SafeContinuation(_hx_continuation);

        func(safe);
	
		return safe.getOrThrow();
    }

    public static function start(block:IContinuation<Any>->Any):Any {
        return startWith(block, new EventLoopScheduler(Thread.current().events));
    }

    public static function startWith(block:IContinuation<Any>->Any, scheduler:IScheduler) {
        return launchWith(block, scheduler).await();
    }

    public static function launch(block:IContinuation<Any>->Any):Task {
        return new Task(new BlockingContinuation(new EventLoopScheduler(Thread.current().events)), block);
    }

    public static function launchWith(block:IContinuation<Any>->Any, scheduler:IScheduler):Task {
        return new Task(new BlockingContinuation(scheduler), block);
    }

    public static macro function isCancellationRequested():haxe.macro.Expr.ExprOf<Bool> {
        return macro _hx_continuation._hx_context.token.isCancellationRequested;
    }
}

class Task {
    final completion : BlockingContinuation;

    final block : IContinuation<Any>->Any;

    public function new(completion, block) {
        this.completion = completion;
        this.block      = block;
    }

    public function await():Any {
        final token = block(completion);

        if (token == Primitive.suspended) {
            return completion.wait();
        } else {
            return token;
        }
    }

    public function cancel() {
        completion.cancel();
    }
}


private class SafeContinuation<T> implements IContinuation<T> {
    final _hx_completion:IContinuation<Any>;
    
    final lock:Mutex;

    var assigned:Bool;

    var _hx_result:Any;

    var _hx_error:Any;

	public final _hx_context:CoroutineContext;

    public function new(completion) {
        _hx_completion = completion;
        _hx_context    = _hx_completion._hx_context;
        _hx_result     = null;
        _hx_error      = null;
        assigned       = false;
        lock           = new Mutex();
    }

    public function resume(result:T, error:Exception) {
        _hx_context.scheduler.schedule(() -> {
            lock.acquire();

            if (assigned) {
                lock.release();
    
                _hx_completion.resume(result, error);
            } else {
                assigned   = true;
                _hx_result = result;
                _hx_error  = error;

                lock.release();
            }
        });
    }

    public function getOrThrow():Any {
        lock.acquire();

        if (assigned) {
            if (_hx_error != null) {
                final tmp = _hx_error;

                lock.release();

                throw tmp;
            }

            final tmp = _hx_result;

            lock.release();

            return tmp;
        }

        assigned = true;

        lock.release();

        return coro.Primitive.suspended;
    }
}
private class BlockingContinuation implements IContinuation<Any> {
	final source:CancellationTokenSource;

	public final _hx_context:CoroutineContext;
	var running : Bool;
	var result : Int;
	var error : Exception;

	public function new(scheduler) {
		source      = new CancellationTokenSource();
		_hx_context = new CoroutineContext(scheduler, source.token);
		running     = true;
		result      = 0;
		error       = null;
	}

	public function resume(result:Any, error:Exception) {
		running = false;

		this.result = result;
		this.error  = error;
	}

	public function wait():Any {
		while (running) {
			Thread.current().events.progress();
		}

		if (error != null) {
			throw error;
		} else {
			return cast result;
		}
	}

	public function cancel() {
		source.cancel();
	}
}