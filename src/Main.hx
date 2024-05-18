import coro.schedulers.ThreadPoolScheduler;
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

		// throw new Exception('bye');

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
		trace(Coroutine.start(someAsync));

		final task = Coroutine.launch(cancellationTesting);

		Timer.delay(task.cancel, 2000);

		trace(task.await());
	}
}