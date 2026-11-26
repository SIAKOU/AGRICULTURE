<?php
/**
 * ============================================
 * proxy-api.php — AgriIntel360 (LWS mutualisé)
 * Description : Proxy HTTP générique vers le backend FastAPI (uvicorn)
 *               sur 127.0.0.1:8001.
 * Auteur : Agent DevOps AgriIntel360
 *
 * Rôle : Apache (mutualisé) n'autorise pas mod_proxy. Ce script PHP
 *        transmet méthode, en-têtes, query string et corps JSON vers
 *        uvicorn, puis renvoie la réponse (statut + corps + headers).
 *        Il est appelé par .htaccess pour toute requête sous /api/.
 * ============================================
 */

// ---------- Cible backend ----------
$backend = 'http://127.0.0.1:8001';

// Reconstruction du chemin API : le préfixe EST CONSERVÉ.
//
// L'ancienne version retirait « /api » (preg_replace('#^/api#', ...)), ce qui
// envoyait /api/v1/health vers http://127.0.0.1:8001/v1/health. L'application
// déclare ses routes sous /api/v1 (settings.API_V1_STR) : toutes les requêtes
// répondaient donc 404. Le chemin complet est transmis tel quel, et
// ws-tunnel.php fait déjà de même — les deux proxys sont cohérents.
$path   = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$target = $backend . $path;

// Query string transmise telle quelle
$qs = isset($_SERVER['QUERY_STRING']) ? $_SERVER['QUERY_STRING'] : '';
if ($qs !== '') {
    $target .= '?' . $qs;
}

// ---------- Méthode & en-têtes ----------
$method  = $_SERVER['REQUEST_METHOD'];
$headers = array(
    'Content-Type: application/json',
    'X-Requested-With: XMLHttpRequest',
    'Accept: application/json',
    'Cache-Control: no-cache',
    'Pragma: no-cache',
);

// Transmission des en-têtes pertinents du client
foreach (array('Authorization', 'X-CSRF-Token', 'Accept-Language', 'Origin', 'Cookie', 'User-Agent') as $h) {
    $key = 'HTTP_' . str_replace('-', '_', strtoupper($h));
    if (isset($_SERVER[$key])) {
        $headers[] = $h . ': ' . $_SERVER[$key];
    }
}

// ---------- Corps de la requête ----------
$body = file_get_contents('php://input');

// ---------- Envoi ----------
$opts = array(
    'http' => array(
        'method'        => $method,
        'header'        => implode("\r\n", $headers),
        'content'       => $body,
        'timeout'       => 55,          // uvicorn peut mettre du temps (génération ML)
        'ignore_errors' => true,        // récupérer le statut même en cas d'erreur 4xx/5xx
        'protocol_version' => '1.1',
    ),
);
$ctx  = stream_context_create($opts);
$resp = @file_get_contents($target, false, $ctx);

// ---------- Réponse ----------
$respHeaders = isset($http_response_header) ? $http_response_header : array();
$status = 502; // par défaut : backend injoignable
foreach ($respHeaders as $line) {
    if (preg_match('#^HTTP/\S+\s+(\d+)#', $line, $m)) {
        $status = (int) $m[1];
        break;
    }
}

http_response_code($status);

if ($resp !== false) {
    // Retransmission des en-têtes utiles (sans Content-Length double)
    foreach ($respHeaders as $line) {
        if (preg_match('#^(Content-Type|Cache-Control|X-RateLimit|X-|Set-Cookie|Access-Control-Allow-Origin|Access-Control-Expose-Headers):\s?(.*)$#i', $line, $m)) {
            if (stripos($m[1], 'Content-Length') === 0) continue;
            header($line, false);
        }
    }
    header('X-Proxied-By: proxy-api.php');
    echo $resp;
} else {
    header('Content-Type: application/json');
    echo json_encode(array(
        'error'   => 'backend_unreachable',
        'message' => 'Le backend AgriIntel360 ne répond pas (uvicorn sur 127.0.0.1:8001). Vérifiez start-backend.sh.',
        'status'  => $status,
    ));
}
