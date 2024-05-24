import coro.CancellationTokenSource;
import coro.CoroutineContext;
import haxe.Exception;
import coro.IContinuation;

class NodeContinuation implements IContinuation<Any> {
    final source : CancellationTokenSource;

    public final _hx_context:CoroutineContext;

    public function new(scheduler) {
        source      = new CancellationTokenSource();
		_hx_context = new CoroutineContext(scheduler, source.token);
    }
    
    public function resume(result:Any, error:Exception) {
        if (error != null) {
			throw error;
		}

		trace(result);
    }

    public function cancel() {
		source.cancel();
	}
}
