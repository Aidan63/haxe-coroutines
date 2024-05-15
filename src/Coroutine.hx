import sys.thread.Thread;
import haxe.Exception;

typedef Continuation<T> = (result:T, error:Exception)->Void;

// class Coroutine {
//     public static function suspend<T>(f:(T->Void)->Void, cont:Continuation<T>):CoroutineResult {
//         Thread.current().events.run(() -> {
// 			f(cont);
// 		});

// 		return Suspended;
//     }
// }

enum CoroutineResult {
    Suspended;
    Success(v:Dynamic);
    Error(exn:Dynamic);
}