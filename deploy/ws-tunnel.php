<?php
/**
 * ============================================
 * ws-tunnel.php — AgriIntel360 (LWS mutualisé)
 * Description : Tunnel WebSocket brut (raw TCP) vers le backend FastAPI
 *               (uvicorn) sur 127.0.0.1:8001.
 * Auteur : Agent DevOps AgriIntel360
 *
 * Rôle : Apache mutualisé n'autorise pas mod_proxy_wstunnel. Ce script
 *        relaie la connexion wss:// vers uvicorn : le handshake WS puis
 *        les trames sont transmises telles quelles (tunneling bidirectionnel).
 *
 * Pré-requis : PHP exécuté en module Apache (mod_php) ou CGI (accès au
 *              socket client via php://stdin). En FastCGI/FPM le tunnel
 *              est limité — le client Socket.IO bascule alors automatiquement
 *              sur le transport long-polling (HTTP), géré par proxy-api.php.
 * ============================================
 */

set_time_limit(0);

$host = '127.0.0.1';
$port = 8001;

// ---------- Connexion au backend ----------
$remote = @stream_socket_client("tcp://$host:$port", $errno, $errstr, 15);
if (!$remote) {
    header('HTTP/1.1 502 Bad Gateway');
    header('Content-Type: text/plain');
    echo 'backend_unreachable';
    exit;
}

// ---------- Reconstruction du handshake HTTP ----------
$method = isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : 'GET';
$uri    = isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '/';
$proto  = isset($_SERVER['SERVER_PROTOCOL']) ? $_SERVER['SERVER_PROTOCOL'] : 'HTTP/1.1';
$head   = "$method $uri $proto\r\n";

foreach ($_SERVER as $k => $v) {
    if (strpos($k, 'HTTP_') === 0) {
        $name = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($k, 5)))));
        $head .= "$name: $v\r\n";
    }
}
$head .= "Connection: Upgrade\r\n";
$head .= "Upgrade: websocket\r\n";
$hostHeader = isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : "$host:$port";
$head .= "Host: $hostHeader\r\n\r\n";

fwrite($remote, $head);
fflush($remote);

// ---------- Mode streaming : désactive toutes les buffers ----------
if (function_exists('apache_setenv')) {
    @apache_setenv('no-gzip', '1');
    @apache_setenv('no-buffering', '1');
}
@ini_set('output_buffering', 'off');
@ini_set('zlib.output_compression', 'off');
@header_remove('Content-Length');
while (ob_get_level()) {
    @ob_end_flush();
}
@flush();

// ---------- Tunneling bidirectionnel ----------
// $client = flux entrant (socket client) ; $remote = flux vers uvicorn
$client = fopen('php://stdin', 'r');
if (!$client) {
    $client = fopen('php://input', 'r');
}
stream_set_blocking($remote, false);
if ($client) {
    stream_set_blocking($client, false);
}

while (!feof($remote)) {
    $read   = array($remote);
    $write  = null;
    $except = null;
    if ($client) {
        $read[] = $client;
    }
    if (@stream_select($read, $write, $except, 1) > 0) {
        foreach ($read as $stream) {
            $data = fread($stream, 65536);
            if ($data === false || $data === '') {
                break 2;
            }
            if ($stream === $remote) {
                echo $data;
                @flush();
            } else {
                fwrite($remote, $data);
                fflush($remote);
            }
        }
    }
}

@fclose($remote);
if ($client) {
    @fclose($client);
}
