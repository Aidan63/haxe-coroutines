import haxe.Exception;
import Coroutine;
import sys.thread.Thread;

@:build(Macro.build())
class Main {
	// some async API
	static var nextNumber = 0;
	static function getNumber(cb:Continuation<Int>) cb(++nextNumber, null);
	// static function getNumberPromise() return new Promise((resolve,_) -> getNumber(resolve));

	// known (hard-coded for now) suspending functions
	inline static function await<T>(func:(cont:Continuation<T>)->Void, cont:Continuation<T>):CoroutineResult {
		Thread.current().events.run(() -> {
			func(cont);
		});

		return Suspended;
	}

	// inline static function awaitPromise<T>(p:Promise<T>, cont:Continuation<T>):Void
	// 	p.then(cont);

	static function test(n:Int, cont:Continuation<String>):Void
		cont('hi $n times', null);

	@:suspend static function someAsync():Int {
		trace("hi");
		while (await(getNumber) < 10) {
			trace('wait for it...');

			trace(await(getNumber));

			// var promise = getNumberPromise();
			// trace(awaitPromise(promise));
		}
		trace("bye");
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
		var coro = someAsync((result, error) -> trace("Result: " + result));
		coro(0, null); // start

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
