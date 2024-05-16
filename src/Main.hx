import haxe.Timer;
import sys.thread.FixedThreadPool;
import sys.thread.IThreadPool;
import sys.thread.EventLoop;
import haxe.io.Bytes;
import asys.native.system.Process;
import sys.thread.Thread;
import haxe.Exception;
import Coroutine;

@:build(Macro.build())
class Main {
	static var nextNumber = 0;

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

				cont.resume(null, new CancellationException());
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
				trace('Hello from thread ${ @:privateAccess Thread.current().handle() }');

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
		trace('coro from thread ${ @:privateAccess Thread.current().handle() }');

		spawnThread();

		trace('coro from thread ${ @:privateAccess Thread.current().handle() }');

		return 0;
	}

	@:suspend static function cancellationTesting():Int {
		trace('starting long delay...');

		delay(10000);

		trace('delay over!');

		return 0;
	}

	static function main() {
		final pool    = new FixedThreadPool(4);
		final blocker = new WaitingCompletion(new EventLoopScheduler(Thread.current().events));
		final result  = switch cancellationTesting(blocker) {
			case Suspended:
				Timer.delay(blocker.cancel, 2000);

				blocker.wait();
			case Success(v):
				v;
			case Error(exn):
				throw exn;
		}

		trace(result);
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

private class WaitingCompletion implements IContinuation<Any> {
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

	public function wait():Int {
		while (running) {
			Thread.current().events.progress();
		}

		if (error != null) {
			throw error;
		} else {
			return result;
		}
	}

	public function cancel() {
		source.cancel();
	}
}