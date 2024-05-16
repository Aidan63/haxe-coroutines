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
			// Process.current.stdout.write(Bytes.ofString(string), 0, string.length, (result, error) -> {
			// 	switch error {
			// 		case null:
			// 			cont(result, null);
			// 		case exn:
			// 			cont(0, exn);
			// 	}
			// });
		});
	}

	@:suspend static function read():String {
		return Coroutine.suspend(cont -> {
			Thread.current().events.run(() -> {
				cont.resume(Sys.stdin().readLine(), null);
			});

			// final buffer = Bytes.alloc(1024);

			// Process.current.stdin.read(buffer, 0, buffer.length, (result, error) -> {
			// 	switch error {
			// 		case null:
			// 			cont(buffer.sub(0, result).toString(), null);
			// 		case exn:
			// 			cont(null, exn);
			// 	}
			// });
		});
	}

	// @:suspend static function read():String {
	// 	return Coroutine.suspend(cont -> {
	// 		final buffer = Bytes.alloc(1024);

	// 		Process.current.stdin.read(buffer, 0, buffer.length, (result, error) -> {
	// 			switch error {
	// 				case null:
	// 					cont(buffer.sub(0, result).toString(), null);
	// 				case exn:
	// 					cont(null, exn);
	// 			}
	// 		});
	// 	});
	// }

	@:suspend static function delay(ms:Int):Void {
		return Coroutine.suspend(cont -> {
			haxe.Timer.delay(() -> cont.resume(null, null), ms);
		});
	}

	@:suspend static function getNumber():Int {
		return Coroutine.suspend(cont -> {
			cont.resume(++nextNumber, null);
		});
	}

	@:suspend static function someAsync():Int {
		trace("hi");

		while (getNumber() < 10) {
			write('wait for it...');

			delay(1000);

			write(Std.string(getNumber()));
		}
		// throw 'bye';
		return 15;
	}

	static function main() {
		final blocker = new WaitingCompletion(new EventLoopScheduler(Thread.current().events));
		final result  = switch someAsync(blocker) {
			case Suspended:
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

private class WaitingCompletion implements IContinuation<Any> {
	public final _hx_context:CoroutineContext;
	var running : Bool;
	var result : Int;
	var error : Exception;

	public function new(scheduler) {
		_hx_context = new CoroutineContext(scheduler);
		running = true;
		result  = 0;
		error   = null;
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
}