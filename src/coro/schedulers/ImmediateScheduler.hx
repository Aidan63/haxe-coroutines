package coro.schedulers;

class ImmediateScheduler implements IScheduler {
	public function new() {}

	public function schedule(func:() -> Void) {
		func();
	}
}