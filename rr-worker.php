<?php
require __DIR__ . '/vendor/autoload.php';
use Spiral\RoadRunner;
use Nyholm\Psr7;
$worker = RoadRunner\Worker::create();
$psrFactory = new Psr7\Factory\Psr17Factory();
$httpWorker = new RoadRunner\Http\Worker($worker, $psrFactory, $psrFactory, $psrFactory);
while ($req = $httpWorker->waitRequest()) {
    try {
        $rsp = $psrFactory->createResponse();
        $rsp->getBody()->write("Hello World!");
        $httpWorker->respond($rsp);
    } catch (\Throwable $e) {
        $httpWorker->getWorker()->error((string)$e);
    }
}
