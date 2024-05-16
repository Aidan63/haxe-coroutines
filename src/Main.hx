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

				cont(string.length, null);
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
				cont(Sys.stdin().readLine(), null);
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
			haxe.Timer.delay(() -> cont(null, null), ms);
		});
	}

	@:suspend static function getNumber():Int {
		return Coroutine.suspend(cont -> {
			cont(++nextNumber, null);
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

	// @:suspend static function fibonacci(yield):Void {
	// 	yield(1); // first Fibonacci number
	// 	var cur = 1;
	// 	var next = 1;
	// 	while (true) {
	// 		yield(next); // next Fibonacci number
	// 		var tmp = cur + next;
	// 		cur = next;
	// 		next = tmp;
	// 	}
	// }

	static function main() {
		var running = true;
		var result  = 0;
		var error   = null;

		var coro    = someAsync((v, exn) -> {
			running = false;

			if (exn != null) {
				error = exn;
			} else {
				result = v;
			}

			return null;
		});
		switch coro(0, null) {
			case Suspended:
				while (running) {
					Thread.current().events.progress();
				}

				if (error != null) {
					throw error;
				} else {
					trace(result);
				}
			case Success(v):
				trace(v);
			case Error(exn):
				throw exn;
		}

		// for (v in new Gen(fibonacci)) {
		// 	trace(v);
		// 	if (v > 10000)
		// 		break;
		// }
	}
}

// typedef Yield<T> = T->Continuation<Any>->Void;

// enum GenState {
// 	NotReady;
// 	Ready;
// 	Done;
// 	Failed;
// }

// class Gen {
// 	var nextStep:Continuation<Any>;
// 	var nextValue:Int;
// 	var state:GenState;

// 	public function new(cont:Yield<Int>->Continuation<Dynamic>->Continuation<Any>) {
// 		nextStep = cont(yield, done);
// 		state = NotReady;
// 	}

// 	function yield(value:Int, next:Continuation<Dynamic>) {
// 		nextValue = value;
// 		state = Ready;
// 	}

// 	function done(result:Any) {
// 		state = Done;
// 	}

// 	public function hasNext():Bool {
// 		return switch state {
// 			case Done: false;
// 			case Ready: true;
// 			case _:
// 				state = Failed;
// 				nextStep(null);
// 				state == Ready;
// 		}
// 	}

// 	public function next():Int {
// 		if (!hasNext()) throw "no more";
// 		state = NotReady;
// 		return nextValue;
// 	}
// }
