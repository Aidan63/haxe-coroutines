package coro.schedulers;

private class ImmediateScheduler implements IScheduler {
	public function new() {}

	public function schedule(func:() -> Void) {
		func();
	}
}