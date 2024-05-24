package coro.schedulers;

import sys.thread.EventLoop;

class EventLoopScheduler implements IScheduler {
    final loop : EventLoop;

    public function new(loop) {
        this.loop = loop;
    }

    public function schedule(func : ()->Void) {
        loop.run(func);
    }
}