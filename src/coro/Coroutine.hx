package coro;

import sys.thread.Mutex;
import haxe.Exception;

@:build(coro.macro.Macro.build())
class Coroutine<T> {
    @:suspend public static function suspend(func:(IContinuation<Any>)->Void):Any {
        final cont = coro.CoroutineIntrinsics.currentContinuation();
        final safe = new SafeContinuation(cont);

        func(safe);
	
		return safe.getOrThrow();
    }
}

abstract class Coroutine0<TReturn> extends Coroutine<Void->TReturn> {
	public abstract function create(completion:IContinuation<Any>):IContinuation<Any>;

	public abstract function start(completion:IContinuation<Any>):Any;
}

abstract class Coroutine1<TArg0, TReturn> extends Coroutine<TArg0->TReturn> {
	public abstract function create(arg0:TArg0, completion:IContinuation<Any>):IContinuation<Any>;

	public abstract function start(arg0:TArg0, completion:IContinuation<Any>):Any;
}

abstract class Coroutine2<TArg0, TArg1, TReturn> extends Coroutine<TArg0->TArg1->TReturn> {
	public abstract function create(arg0:TArg0, arg1:TArg1, completion:IContinuation<Any>):IContinuation<Any>;

	public abstract function start(arg0:TArg0, arg1:TArg1, completion:IContinuation<Any>):Any;
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