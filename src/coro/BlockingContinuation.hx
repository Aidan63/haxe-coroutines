package coro;

import sys.thread.Thread;
import haxe.Exception;

class BlockingContinuation implements IContinuation<Any> {
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