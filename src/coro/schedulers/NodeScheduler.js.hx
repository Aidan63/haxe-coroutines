package coro.schedulers;

import js.Node;

class NodeScheduler implements IScheduler {
    public function new() {}

    public function schedule(func:() -> Void) {
        Node.setImmediate(func);
    }
}