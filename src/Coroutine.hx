import sys.thread.Thread;
import haxe.Exception;

interface IContinuation<T> {
	function resume(result:T, error:Exception):Void;
}

class Coroutine {
    @:suspend public static function suspend(func:(IContinuation<Any>)->Void, cont:IContinuation<Any>):CoroutineResult<Any> {
		Thread.current().events.run(() -> {
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