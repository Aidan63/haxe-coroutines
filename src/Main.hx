import haxe.Timer;
import sys.thread.FixedThreadPool;
import sys.thread.IThreadPool;
import sys.thread.EventLoop;
import haxe.io.Bytes;
import sys.thread.Thread;
import haxe.Exception;
import Coroutine;

@:build(Macro.build())
class Main {
	static var nextNumber = 0;

	static var accumulated = 0;

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
			var handle : EventHandler = null;

			final events = Thread.current().events;

			handle = events.repeat(() -> {
				events.cancel(handle);

				cont.resume(null, null);
			}, ms);

			cont._hx_context.token.register(() -> {
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

	@:suspend static function spawnThread():Void {
		return Coroutine.suspend(cont -> {
			Thread.create(() -> {
#if cpp
				trace('Hello from thread ${ untyped Thread.current().handle }');
#else
				trace('Hello from thread ${ Thread.current() }');
#end

				cont.resume(null, null);
			});
		});
	}

	@:suspend static function someAsync():Int {
		trace("hi");

		while (getNumber() < 10) {
			write('wait for it...');

			delay(1000);

			write(Std.string(getNumber()));
		}

		return 15;
	}

	@:suspend static function schedulerTesting():Int {
#if cpp
		trace('coro from thread ${ untyped Thread.current().handle }');
#else
		trace('coro from thread ${ Thread.current() }');
#end

		spawnThread();

#if cpp
		trace('coro from thread ${ untyped Thread.current().handle }');
#else
		trace('coro from thread ${ Thread.current() }');
#end

		return 0;
	}

	@:suspend static function cancellationTesting():Int {
		trace('starting long delay...');

		delay(10000);

		trace('delay over!');

		return 0;
	}

	@:suspend static function cooperativeCancellation():Int {
		trace('starting work');

		while (Coroutine.isCancellationRequested() == false) {
			accumulated = getNumber();
		}

		return accumulated;
	}

	static function main() {
		// final pool    = new FixedThreadPool(4);
		// final blocker = new WaitingCompletion(new EventLoopScheduler(Thread.current().events));
		// final result  = switch someAsync(blocker) {
		// 	case Suspended:
		// 		// Timer.delay(blocker.cancel, 2000);

		// 		blocker.wait();
		// 	case Success(v):
		// 		v;
		// 	case Error(exn):
		// 		throw exn;
		// }

		// trace(result);

		trace(Coroutine.start(someAsync));
	}
}

private class ImmediateScheduler implements IScheduler {
	public function new() {}

	public function schedule(func:() -> Void) {
		func();
	}
}

private class EventLoopScheduler implements IScheduler {
	final loop:EventLoop;

	public function new(loop) {
		this.loop = loop;
	}

	public function schedule(func:() -> Void) {
		loop.run(func);
	}
}

private class NewThreadScheduler implements IScheduler {
	public function new() {}

	public function schedule(func:() -> Void) {
		Thread.create(func);
	}
}

private class ThreadPoolScheduler implements IScheduler {
	final pool : IThreadPool;

	public function new(pool) {
		this.pool = pool;
	}

	public function schedule(func:() -> Void) {
		pool.run(func);
	}
}

private class WaitingCompletion<T> implements IContinuation<Any> {
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

	public function wait():T {
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