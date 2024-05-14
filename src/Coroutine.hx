import sys.thread.Thread;
import Main.Continuation;

class Coroutine {
    public static function suspend<T>(f:(T->Void)->Void, cont:Continuation<T>):CoroutineResult {
        Thread.current().events.run(() -> {
			f(cont);
		});

		return Suspended;
    }
}

enum CoroutineResult {
    Suspended;
    Success(v:Dynamic);
    Error(exn:Dynamic);
}