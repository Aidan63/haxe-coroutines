package coro.schedulers;

interface IScheduler {
    function schedule(func:()->Void):Void;
}