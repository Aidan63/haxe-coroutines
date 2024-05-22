package coro;

import haxe.exceptions.CancellationException;

abstract Registration(()->Void) {
    public function new(func:()->Void) {
        this = func;
    }

    public function unregister() {
        this();
    }
}

class CancellationTokenSource {
    var cancelled:Bool;

    final registrations:Array<()->Void>;

    public final token:CancellationToken;

    public var isCancellationRequested(get, never):Bool;

    public function get_isCancellationRequested() {
        return cancelled;
    }

    public function new() {
        token         = new CancellationToken(this);
        cancelled     = false;
        registrations = [];
    }

    public function register(func:()->Void):Registration {
        if (isCancellationRequested) {
            throw new CancellationException('Cancellation token has already been cancelled');
        }

        registrations.push(func);

        return new Registration(() -> registrations.remove(func));
    }

    public function cancel() {
        if (isCancellationRequested) {
            throw new CancellationException('Cancellation token has already been cancelled');
        }

        cancelled = true;

        for (func in registrations) {
            func();
        }
    }
}