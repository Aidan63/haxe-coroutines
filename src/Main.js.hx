import js.node.Timers;
import coro.Coroutine;
import coro.IContinuation;
import coro.CoroutineContext;
import coro.CoroutineIntrinsics;
import coro.schedulers.NodeScheduler;
import coro.CancellationTokenSource;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import utest.Test;
import utest.Async;
import utest.Assert;

@:build(Macro.build())
class Main extends Test {
	static var nextNumber = 0;

	static var accumulated = 0;

	@:suspend static function write(string:String):Int {
		return Coroutine.suspend(cont -> {
			js.Node.process.stdout.write(string + '\n', null, () -> {
				cont.resume(0, null);
			});
		});
	}

	@:suspend static function delay(ms:Int):Void {
		return Coroutine.suspend(cont -> {
			var handle       : Timeout = null;
			var registration : Registration = null;

			handle = js.Node.setTimeout(() -> {
				registration.unregister();

				cont.resume(null, null);
			}, ms);

			registration = cont._hx_context.token.register(() -> {
				js.Node.clearInterval(handle);

				cont.resume(null, new CancellationException('delay has been cancelled'));
			});
		});
	}

	@:suspend static function getNumber():Int {
		return Coroutine.suspend(cont -> {
			cont.resume(++nextNumber, null);
		});
	}

	@:suspend static function someAsync():Int {
		write("hi");

		while (getNumber() < 10) {
			write('wait for it...');

			delay(100);

			write(Std.string(getNumber()));
		}

		return 15;
	}

	@:suspend static function cancellationTesting():Void {
		write('starting long delay...');

		delay(10000);

		write('delay over!');
	}

	@:suspend static function cooperativeCancellation():Int {
		trace('starting work');

		while (CoroutineIntrinsics.currentContinuation()._hx_context.token.isCancellationRequested == false) {
			accumulated = getNumber();
		}

		return accumulated;
	}

	function new() {
		super();
	}

	function setup() {
		nextNumber  = 0;
		accumulated = 0;
	}

	@:timeout(1000)
	function test_complex_continuation(async:Async) {
		final cont = new CallbackContinuation(new NodeScheduler(), (result, error) -> {
			Assert.isNull(error);
			Assert.equals(result, 15);

			async.done();
		});

		CoroutineIntrinsics.create(someAsync, cont).resume(null, null);
	}

	function test_cancellation(async:Async) {
		final cont = new CallbackContinuation(new NodeScheduler(), (result, error) -> {
			Assert.isNull(result);
			Assert.isOfType(error, CancellationException);

			async.done();
		});

		CoroutineIntrinsics.create(cancellationTesting, cont).resume(null, null);
		
		js.Node.setTimeout(cont.cancel, 100);
	}

	function test_cooperative_cancellation(async:Async) {
		final cont = new CallbackContinuation(new NodeScheduler(), (result, error) -> {
			Assert.isNull(error);
			Assert.isTrue((result:Int) > 0);

			async.done();
		});

		CoroutineIntrinsics.create(cooperativeCancellation, cont).resume(null, null);
		
		js.Node.setTimeout(cont.cancel, 100);
	}

	static function main() {
		utest.UTest.run([ new Main() ]);
	}
}

private class NodeContinuation implements IContinuation<Any> {
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

private class CallbackContinuation implements IContinuation<Any> {
	final source : CancellationTokenSource;

	final callback : (result:Any, error:Exception)->Void;

    public final _hx_context:CoroutineContext;

    public function new(scheduler, callback) {
		this.callback = callback;

        source      = new CancellationTokenSource();
		_hx_context = new CoroutineContext(scheduler, source.token);
    }
    
    public function resume(result:Any, error:Exception) {
        callback(result, error);
    }

    public function cancel() {
		source.cancel();
	}
}