package coro;

import haxe.Exception;

@:build(coro.macro.Macro.build())
class Coroutine {
    @:suspend public static function suspend(func:(IContinuation<Any>)->Void):Any {
        final cont = coro.CoroutineIntrinsics.currentContinuation();
        final safe = new SafeContinuation(cont);

        func(safe);
	
		return safe.getOrThrow();
    }
}

private class SafeContinuation<T> implements IContinuation<T> {
    final _hx_completion:IContinuation<Any>;

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
    }

    public function resume(result:T, error:Exception) {
        _hx_context.scheduler.schedule(() -> {
            if (assigned) {
                _hx_completion.resume(result, error);
            } else {
                assigned   = true;
                _hx_result = result;
                _hx_error  = error;
            }
        });
    }

    public function getOrThrow():Any {
        if (assigned) {
            if (_hx_error != null) {
                final tmp = _hx_error;

                throw tmp;
            }

            final tmp = _hx_result;

            return tmp;
        }

        assigned = true;

        return coro.Primitive.suspended;
    }
}