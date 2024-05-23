package coro.schedulers;

import sys.thread.Thread;

class NewThreadScheduler implements IScheduler {
	public function new() {}

	public function schedule(func:() -> Void) {
		Thread.create(func);
	}
}