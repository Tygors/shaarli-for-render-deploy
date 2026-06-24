<?php
// Patch Shaarli's PublishController to add backup trigger on bookmark save
$file = '/var/www/shaarli/application/front/controller/admin/ShaarePublishController.php';
$code = file_get_contents($file);

// Find the save method and add a touch call before the closing brace
$target = 'public function save(Request $request, Response $response): Response';
if (strpos($code, $target) === false) {
    echo "WARNING: save method not found in ShaarePublishController\n";
    echo "CHECKING: available methods:\n";
    preg_match_all('/function (\w+)/', $code, $matches);
    foreach ($matches[1] as $m) echo "  - $m\n";
    exit(1);
}
if (strpos($code, $target) === false) {
    echo "WARNING: save method not found in ShaarePublishController\n";
    exit(1);
}

// Find the return statement inside the save method and insert trigger before it
$method_start = strpos($code, $target);
$return_pos = strpos($code, 'return $response', $method_start);
if ($return_pos === false) {
    echo "WARNING: could not find return \$response in save method\n";
    exit(1);
}
// Insert trigger on the line before return
$trigger = "        @touch('/tmp/shaarli-backup-trigger');\n    ";
$code = substr_replace($code, $trigger, $return_pos, 0);

file_put_contents($file, $code);
echo "Patched save() with backup trigger OK\n";
