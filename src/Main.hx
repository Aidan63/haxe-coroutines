import js.node.Timers.Timeout;
import coro.schedulers.NodeScheduler;
import coro.schedulers.ImmediateScheduler;
import js.node.Tty;
import js.node.Process;
import haxe.Exception;
import haxe.exceptions.CancellationException;
import coro.Task;
import coro.Coroutine;
import coro.EventLoop;
import coro.BlockingContinuation;
import coro.CancellationTokenSource;
import coro.schedulers.EventLoopScheduler;

@:build(Macro.build())
class Main {
	static var nextNumber = 0;

	static var accumulated = 0;

	static var events : EventLoop;

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

// 	@:suspend static function spawnThread():Void {
// 		Coroutine.suspend(cont -> {
// 			Thread.create(() -> {
// #if cpp
// 				trace('Hello from thread ${ untyped Thread.current().handle }');
// #else
// 				trace('Hello from thread ${ Thread.current() }');
// #end

// 				cont.resume(null, null);
// 			});
// 		});
// 	}

	@:suspend static function someAsync():Int {
		write("hi");

		while (getNumber() < 10) {
			write('wait for it...');

			delay(1000);

			write(Std.string(getNumber()));
		}

		throw new Exception('bye');

		return 15;
	}

// 	@:suspend static function schedulerTesting():Int {
// #if cpp
// 		trace('coro from thread ${ untyped Thread.current().handle }');
// #else
// 		trace('coro from thread ${ Thread.current() }');
// #end

// 		spawnThread();

// #if cpp
// 		trace('coro from thread ${ untyped Thread.current().handle }');
// #else
// 		trace('coro from thread ${ Thread.current() }');
// #end

// 		return 0;
// 	}

// 	@:suspend static function cancellationTesting():Int {
// 		trace('starting long delay...');

// 		delay(10000);

// 		trace('delay over!');

// 		return 0;
// 	}

// 	@:suspend static function cooperativeCancellation():Int {
// 		trace('starting work');

// 		while (CoroutineIntrinsics.isCancellationRequested() == false) {
// 			accumulated = getNumber();
// 		}

// 		return accumulated;
// 	}

	static function main() {
		events = new EventLoop();

		someAsync(new BlockingContinuation(new NodeScheduler(), null));

		// final task = new Task(new BlockingContinuation(new EventLoopScheduler(events), events), someAsync);

		// trace(task.await());

		// trace(Coroutine.startWith(someAsync, new coro.schedulers.ImmediateScheduler()));

		// final cont = CoroutineIntrinsics.create(someAsync, null);

		// final task = Coroutine.launch(cancellationTesting);

		// haxe.Timer.delay(task.cancel, 2000);

		// trace(task.await());
	}
}