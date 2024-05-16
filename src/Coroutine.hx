import haxe.Exception;

interface IScheduler {
    function schedule(func:()->Void):Void;
}

class CoroutineContext {
    public final scheduler:IScheduler;

    public function new(scheduler) {
        this.scheduler = scheduler;
    }
}

interface IContinuation<T> {
    final _hx_context:CoroutineContext;

	function resume(result:T, error:Exception):Void;
}

class Coroutine {
    @:suspend public static function suspend(func:(IContinuation<Any>)->Void, cont:IContinuation<Any>):CoroutineResult<Any> {
        cont._hx_context.scheduler.schedule(() -> {
            func(cont);
        });
	
		return Suspended;
    }
}

enum CoroutineResult<T> {
    Suspended;
    Success(v:T);
    Error(exn:Dynamic);
}