import sys.thread.Thread;
import sys.thread.EventLoop;
import coro.Coroutine;
import coro.Coroutine.Coroutine0;
import coro.IContinuation;
import coro.CoroutineContext;
import coro.CoroutineIntrinsics;
import coro.CancellationTokenSource;
import coro.schedulers.EventLoopScheduler;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import utest.Test;
import utest.Async;
import utest.Assert;

@:build(coro.macro.Macro.build())
class Main extends Test {
	static var nextNumber = 0;

	static var accumulated = 0;

	static var threads = new Array<String>();

	@:suspend static function write(string:String):Int {
		return Coroutine.suspend(cont -> {
			Thread.current().events.run(() -> {
				Sys.println(string);

				cont.resume(string.length, null);
			});
		});
	}

	@:suspend static function delay(ms:Int):Void {
		return Coroutine.suspend(cont -> {
			var handle       : EventHandler = null;
			var registration : Registration = null;

			final events = Thread.current().events;

			handle = events.repeat(() -> {
				events.cancel(handle);
				registration.unregister();

				cont.resume(null, null);
			}, ms);

			registration = cont._hx_context.token.register(() -> {
				events.cancel(handle);

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

	@:suspend static function coroParameter(c:coro.Coroutine<()->Int>):Int {
		trace('before');

		return c.start();
	}

	@:suspend static function spawnThread():Void {
		Coroutine.suspend(cont -> {
			Thread.create(() -> {
#if cpp
				threads.push(untyped Thread.current().handle);
#else
				threads.push(Std.string(Thread.current()));
#end

				cont.resume(null, null);
			});
		});
	}

	@:suspend static function schedulerTesting():Void {
#if cpp
		threads.push(untyped Thread.current().handle);
#else
		threads.push(Std.string(Thread.current()));
#end

		spawnThread();

#if cpp
		threads.push(untyped Thread.current().handle);
#else
		threads.push(Std.string(Thread.current()));
#end
	}

	function new() {
		super();
	}

	function setup() {
		nextNumber  = 0;
		accumulated = 0;
		threads     = [];
	}

	@:timeout(1000)
	function test_complex_continuation(async:Async) {
		final cont = new CallbackContinuation(new EventLoopScheduler(Thread.current().events), (result, error) -> {
			Assert.isNull(error);
			Assert.equals(result, 15);

			async.done();
		});

		CoroutineIntrinsics.create(someAsync, cont).resume(null, null);
	}

	function test_cancellation(async:Async) {
		final cont = new CallbackContinuation(new EventLoopScheduler(Thread.current().events), (result, error) -> {
			Assert.isNull(result);
			Assert.isOfType(error, CancellationException);

			async.done();
		});

		CoroutineIntrinsics.create(cancellationTesting, cont).resume(null, null);
		
		haxe.Timer.delay(cont.cancel, 100);
	}

	function test_cooperative_cancellation(async:Async) {
		final cont = new CallbackContinuation(new EventLoopScheduler(Thread.current().events), (result, error) -> {
			Assert.isNull(error);
			Assert.isTrue((result:Int) > 0);

			async.done();
		});

		CoroutineIntrinsics.create(cooperativeCancellation, cont).resume(null, null);
		
        haxe.Timer.delay(cont.cancel, 100);
	}

    function test_blocking_result() {
        final cont = new BlockingContinuation(new EventLoopScheduler(Thread.current().events));

		CoroutineIntrinsics.create(someAsync, cont).resume(null, null);

        Assert.equals(cont.wait(), 15);
    }

    function test_blocking_throw() {
        final cont = new BlockingContinuation(new EventLoopScheduler(Thread.current().events));

		CoroutineIntrinsics.create(someAsync, cont).resume(null, null);

        haxe.Timer.delay(cont.cancel, 100);

        Assert.exception(cont.wait, CancellationException);
    }

	function test_scheduler(async:Async) {
		final cont = new CallbackContinuation(new EventLoopScheduler(Thread.current().events), (result, error) -> {
			Assert.isNull(error);
			Assert.isNull(result);

			Assert.equals(3, threads.length);
			Assert.equals(threads[0], threads[2]);
			Assert.notEquals(threads[1], threads[0]);
			Assert.notEquals(threads[1], threads[2]);

			async.done();
		});

		CoroutineIntrinsics.create(schedulerTesting, cont).resume(null, null);
	}

	function test_coro_param(async:Async) {
		final cont = new CallbackContinuation(new EventLoopScheduler(Thread.current().events), (result, error) -> {
			Assert.isNull(error);
			Assert.equals(result, 1);

			async.done();
		});

		CoroutineIntrinsics.create(coroParameter, new HxCoro_getNumber(null), cont).resume(null, null);
	}

	static function main() {
		utest.UTest.run([ new Main() ]);
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

private class BlockingContinuation implements IContinuation<Any> {
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