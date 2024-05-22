package coro;

class CancellationToken {
    final source:CancellationTokenSource;

    public var isCancellationRequested(get, never):Bool;

    public function get_isCancellationRequested() {
        return source.isCancellationRequested;
    }

    public function new(source) {
        this.source = source;
    }

    public function register(func:()->Void) {
        return source.register(func);
    }
}