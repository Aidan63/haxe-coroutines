package coro.schedulers;

import sys.thread.IThreadPool;

class ThreadPoolScheduler implements IScheduler {
	final pool : IThreadPool;

	public function new(pool) {
		this.pool = pool;
	}

	public function schedule(func:() -> Void) {
		pool.run(func);
	}
}