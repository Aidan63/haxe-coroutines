import sys.thread.Thread;
import haxe.Exception;
import Coroutine;

@:build(Macro.build())
class Main {
	static var nextNumber = 0;

	@:suspend static function getNumber():Int {
		return Coroutine.suspend(cont -> {
			cont(++nextNumber, null);
		});
	}

	@:suspend static function someAsync():Int {
		trace("hi");
		while (getNumber() < 10) {
			trace('wait for it...');

			trace(getNumber());
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
