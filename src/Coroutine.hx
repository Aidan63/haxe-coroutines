import sys.thread.Thread;
import haxe.Exception;

typedef Continuation<T> = (result:T, error:Exception)->CoroutineResult;

class Coroutine {
    @:suspend public static function suspend<T>(func:(Continuation<T>)->Void, cont:Continuation<T>):Continuation<T> {
		return function (_, _):CoroutineResult {
			Thread.current().events.run(() -> {
				func(cont);
			});
	
			return Suspended;
		}
    }
}

enum CoroutineResult {
    Suspended;
    Success(v:Dynamic);
    Error(exn:Dynamic);
}