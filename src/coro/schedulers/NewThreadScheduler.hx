package coro.schedulers;

import sys.thread.Thread;

private class NewThreadScheduler implements IScheduler {
	public function new() {}

	public function schedule(func:() -> Void) {
		Thread.create(func);
	}
}